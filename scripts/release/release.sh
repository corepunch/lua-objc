#!/bin/sh
# Builds a bundled app for download from a GitHub release: archive, sign
# with Developer ID, notarize, staple, and wrap it in a DMG.
#
#   scripts/release/release.sh diskmap/1.2.3
#   scripts/release/release.sh dnb/1.2.3
#
# The tag names the app and its version; the DMG is written to
# build/release/<Product>-<version>.dmg and its path printed last.
#
# Signing needs a "Developer ID Application" identity in a keychain the
# build can read. Notarizing needs an App Store Connect API key:
# NOTARY_KEY (path to the .p8), NOTARY_KEY_ID and NOTARY_ISSUER_ID. With
# UNSIGNED=1 the app is signed ad hoc and not notarized, which runs only on
# the Mac that built it; that is how the pipeline is checked without
# credentials.
set -eu

tag=${1:?usage: release.sh <app>/<major.minor.patch>}
app=${tag%%/*}
version=${tag#*/}
team=BM2R8F5YHC

# The apps released this way: tag prefix -> project folder and product.
case "$app" in
	diskmap) product=Diskmap ;;
	dnb) product=DrumAndBass ;;
	*) echo "release.sh: no release for '$app' (diskmap, dnb)" >&2; exit 2 ;;
esac
case "$version" in
	[0-9]*.[0-9]*.[0-9]*) ;;
	*) echo "release.sh: expected a tag like $app/1.2.3, not $tag" >&2; exit 2 ;;
esac

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

if [ "${UNSIGNED:-0}" = 1 ]; then
	# Ad hoc: no team, so no library validation either.
	signing="CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= ENABLE_HARDENED_RUNTIME=NO"
else
	signing="CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=Developer\ ID\ Application DEVELOPMENT_TEAM=$team OTHER_CODE_SIGN_FLAGS=--timestamp"
fi
eval xcodebuild -project "$project" -scheme "$product" -configuration Release \
	-destination "'generic/platform=macOS'" -derivedDataPath build/release/derived \
	-archivePath "$archive" $signing archive -quiet

bundle="$out/$product.app"
if [ "${UNSIGNED:-0}" = 1 ]; then
	ditto "$archive/Products/Applications/$product.app" "$bundle"
else
	cat > "$out/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>developer-id</string>
	<key>signingStyle</key><string>manual</string>
	<key>signingCertificate</key><string>Developer ID Application</string>
	<key>teamID</key><string>$team</string>
</dict>
</plist>
EOF
	xcodebuild -exportArchive -archivePath "$archive" -exportPath "$out" \
		-exportOptionsPlist "$out/ExportOptions.plist" -quiet
fi
codesign --verify --deep --strict "$bundle"

# A DMG with the app beside a link to Applications, to drag it across.
dmg="$out/$product-$version.dmg"
stage="$out/dmg"
mkdir -p "$stage"
ditto "$bundle" "$stage/$product.app"
ln -s /Applications "$stage/Applications"
volume=$(/usr/libexec/PlistBuddy -c "Print CFBundleDisplayName" "$bundle/Contents/Info.plist")
hdiutil create -quiet -volname "$volume $version" -srcfolder "$stage" -fs APFS -format UDZO "$dmg"

if [ "${UNSIGNED:-0}" != 1 ]; then
	codesign --sign "Developer ID Application" --timestamp "$dmg"
	xcrun notarytool submit "$dmg" --key "${NOTARY_KEY:?}" --key-id "${NOTARY_KEY_ID:?}" \
		--issuer "${NOTARY_ISSUER_ID:?}" --wait
	xcrun stapler staple "$dmg"
	spctl --assess --type open --context context:primary-signature "$dmg"
fi
echo "$dmg"
