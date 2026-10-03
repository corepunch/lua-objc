#!/bin/sh
# Builds a bundled app for download from a GitHub release: archive, sign
# for Developer ID, notarize, staple, and wrap it in a DMG.
#
#   scripts/release/release.sh diskmap/1.2.3
#   scripts/release/release.sh dnb/1.2.3
#
# The tag names the app and its version; the DMG is written to
# build/release/<app>/<Product>-<version>.dmg and its path printed last.
#
# Signing, by what the machine has:
# - a "Developer ID Application" identity in a keychain and an App Store
#   Connect API key (NOTARY_KEY, a .p8 path, NOTARY_KEY_ID, NOTARY_ISSUER_ID):
#   signed here, notarized with notarytool, the DMG signed and stapled too.
#   This is the GitHub runner, which imports both from secrets.
# - otherwise, a Mac whose Xcode is signed in to the team: Xcode signs with
#   its cloud-managed Developer ID certificate and submits the app for
#   notarization through the account, then hands back the stapled app. No
#   key or password passes through the script.
# - UNSIGNED=1: signed ad hoc and not notarized, which runs only on the Mac
#   that built it; that is how the pipeline is checked without credentials.
set -eu

tag=${1:?usage: release.sh <app>/<major.minor.patch>}
app=${tag%%/*}
version=${tag#*/}
team=BM2R8F5YHC
# Minutes to wait for Apple's notary service.
notaryMinutes=30

# The apps released this way: tag prefix -> product.
case "$app" in
	diskmap) product=Diskmap ;;
	dnb) product=DrumAndBass ;;
	*) echo "release.sh: no release for '$app' (diskmap, dnb)" >&2; exit 2 ;;
esac
case "$version" in
	[0-9]*.[0-9]*.[0-9]*) ;;
	*) echo "release.sh: expected a tag like $app/1.2.3, not $tag" >&2; exit 2 ;;
esac

if [ "${UNSIGNED:-0}" = 1 ]; then
	signing=adhoc
elif [ -n "${NOTARY_KEY:-}" ] && security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
	signing=keychain
else
	signing=xcode
fi
echo "release.sh: $product $version, signing: $signing" >&2

root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
project="apps/$app/$product.xcodeproj"
out="build/release/$app"
archive="$out/$product.xcarchive"
rm -rf "$out"
mkdir -p "$out"

# The version lives in the app's Info.plist for the length of the build.
plist="apps/$app/Info.plist"
cp "$plist" "$out/Info.plist.orig"
trap 'cp "$out/Info.plist.orig" "$plist"' EXIT
python3 scripts/ipad/release_version.py --prefix "$app" "$tag" "$plist"

exportOptions() {
	cat > "$out/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>developer-id</string>
	<key>teamID</key><string>$team</string>
	$1
</dict>
</plist>
EOF
}

build() {
	xcodebuild -project "$project" -scheme "$product" -configuration Release \
		-destination 'generic/platform=macOS' -derivedDataPath build/release/derived \
		-archivePath "$archive" "$@" archive -quiet
}

bundle="$out/$product.app"
case "$signing" in
adhoc)
	# No team, so no library validation either.
	build CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= ENABLE_HARDENED_RUNTIME=NO
	ditto "$archive/Products/Applications/$product.app" "$bundle"
	;;
keychain)
	build CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=Developer ID Application" DEVELOPMENT_TEAM=$team \
		OTHER_CODE_SIGN_FLAGS=--timestamp
	exportOptions '<key>signingStyle</key><string>manual</string>
	<key>signingCertificate</key><string>Developer ID Application</string>'
	xcodebuild -exportArchive -archivePath "$archive" -exportPath "$out" \
		-exportOptionsPlist "$out/ExportOptions.plist" -quiet
	;;
xcode)
	build -allowProvisioningUpdates
	# destination upload: the export goes to Apple's notary service through
	# the account Xcode is signed in to.
	exportOptions '<key>signingStyle</key><string>automatic</string>
	<key>destination</key><string>upload</string>'
	xcodebuild -exportArchive -archivePath "$archive" -exportPath "$out/upload" \
		-exportOptionsPlist "$out/ExportOptions.plist" -allowProvisioningUpdates
	# The notarized, stapled app is ready once Apple has accepted it.
	waited=0
	until xcodebuild -exportNotarizedApp -archivePath "$archive" -exportPath "$out" >"$out/notary.log" 2>&1; do
		if [ "$waited" -ge $((notaryMinutes * 2)) ]; then
			cat "$out/notary.log" >&2
			echo "release.sh: not notarized after $notaryMinutes minutes" >&2
			exit 1
		fi
		sleep 30
		waited=$((waited + 1))
	done
	xcrun stapler validate "$bundle"
	;;
esac
codesign --verify --deep --strict "$bundle"
if [ "$signing" != adhoc ]; then
	spctl --assess --type execute "$bundle"
fi

# A DMG with the app beside a link to Applications, to drag it across.
dmg="$out/$product-$version.dmg"
stage="$out/dmg"
mkdir -p "$stage"
ditto "$bundle" "$stage/$product.app"
ln -s /Applications "$stage/Applications"
volume=$(/usr/libexec/PlistBuddy -c "Print CFBundleDisplayName" "$bundle/Contents/Info.plist")
hdiutil create -quiet -volname "$volume $version" -srcfolder "$stage" -fs APFS -format UDZO "$dmg"

# The cloud-managed certificate signs only through Xcode, so a DMG made with
# it stays unsigned; the notarized, stapled app inside is what Gatekeeper
# checks.
if [ "$signing" = keychain ]; then
	codesign --sign "Developer ID Application" --timestamp "$dmg"
	xcrun notarytool submit "$dmg" --key "$NOTARY_KEY" --key-id "${NOTARY_KEY_ID:?}" \
		--issuer "${NOTARY_ISSUER_ID:?}" --wait
	xcrun stapler staple "$dmg"
	spctl --assess --type open --context context:primary-signature "$dmg"
fi
echo "$dmg"
