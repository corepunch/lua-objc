#!/usr/bin/env python3
"""Correct Premake beta8's iOS Xcode output before committing it."""
from pathlib import Path
import re


PROJECT = Path('ios/AdventureArena/AdventureArena.xcodeproj/project.pbxproj')


def corrected(source: str) -> str:
    # Premake lists asset catalogs in the navigator but omits their build phase.
    # Register the catalog so actool emits AppIcon and App Store icon metadata.
    asset = re.search(r'([A-F0-9]{24}) /\* Assets\.xcassets \*/ = \{isa = PBXFileReference;', source)
    if not asset:
        raise ValueError('Premake did not include Assets.xcassets')
    build_file = 'AA0000000000000000000001'
    source = source.replace('/* Begin PBXBuildFile section */',
                            f'/* Begin PBXBuildFile section */\n'
                            f'\t\t{build_file} /* Assets.xcassets in Resources */ = '
                            f'{{isa = PBXBuildFile; fileRef = {asset[1]} /* Assets.xcassets */; }};')
    resource_phases = re.findall(r'([A-F0-9]{24}) /\* Resources \*/ = \{', source)
    if len(resource_phases) != 1:
        raise ValueError('Expected one Premake resources phase')
    source = re.sub(rf'({resource_phases[0]} /\* Resources \*/ = \{{.*?files = \(\n)',
                    rf'\1\t\t\t\t{build_file} /* Assets.xcassets in Resources */,\n',
                    source, count=1, flags=re.DOTALL)

    # beta8 serializes single-value xcodebuildsettings as arrays. Xcode expects
    # these signing and product keys to be scalar strings.
    scalar_keys = (
        'ASSETCATALOG_COMPILER_APPICON_NAME', 'CLANG_ENABLE_OBJC_ARC',
        'CODE_SIGN_STYLE', 'DEVELOPMENT_TEAM', 'GENERATE_INFOPLIST_FILE', 'INFOPLIST_FILE',
        'PRODUCT_BUNDLE_IDENTIFIER', 'TARGETED_DEVICE_FAMILY',
    )
    for key in scalar_keys:
        pattern = rf'\b{key} = \(\s*([^,\n]*),\s*\);'
        source, count = re.subn(pattern, lambda m: f'{key} = {m[1]};', source)
        if count != 4:
            raise ValueError(f'Expected four {key} settings, found {count}')
    source = source.replace('INFOPLIST_FILE = ios/AdventureArena/Info.plist;',
                            'INFOPLIST_FILE = Info.plist;')
    source = source.replace('USER_HEADER_SEARCH_PATHS = (', 'HEADER_SEARCH_PATHS = (')
    source, count = re.subn(r'MACOSX_DEPLOYMENT_TARGET = 26\.5;',
                            'IPHONEOS_DEPLOYMENT_TARGET = 26.5;', source)
    if count != 2:
        raise ValueError(f'Expected two deployment settings, found {count}')
    source = source.replace('INSTALL_PATH = "\\"$(HOME)/Applications\\"";',
                            'INSTALL_PATH = /Applications;')
    source = source.replace('productInstallPath = "$(HOME)/Applications";',
                            'productInstallPath = /Applications;')
    # Keep archive intermediates in Xcode's DerivedData, not beside the source.
    source = re.sub(r'^\t{4}(?:CONFIGURATION_BUILD_DIR|CONFIGURATION_TEMP_DIR|OBJROOT|SYMROOT) = .*;\n',
                    '', source, flags=re.MULTILINE)
    source, count = re.subn(r'(PRODUCT_NAME = AdventureArena;)',
                            r'\1\n\t\t\t\tSDKROOT = iphoneos;'
                            r'\n\t\t\t\tSUPPORTED_PLATFORMS = "iphoneos iphonesimulator";'
                            r'\n\t\t\t\tMARKETING_VERSION = 1.0;'
                            r'\n\t\t\t\tCURRENT_PROJECT_VERSION = 1;', source)
    if count != 2:
        raise ValueError(f'Expected two target configurations, found {count}')
    return source


if __name__ == '__main__':
    PROJECT.write_text(corrected(PROJECT.read_text()))
