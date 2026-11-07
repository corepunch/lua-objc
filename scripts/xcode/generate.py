#!/usr/bin/env python3
"""Generate Adventure Arena's native iPhone/iPad Xcode project, beside its app."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / 'apps/adventure-arena'
PROJECT = APP / 'AdventureArena.xcodeproj'


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists() or path.read_text() != text:
        path.write_text(text)


def encode(value, level=0):
    indent = '\t' * level
    if isinstance(value, dict):
        return '{\n' + ''.join(f'{indent}\t{encode(k)} = {encode(v, level + 1)};\n'
                              for k, v in value.items()) + indent + '}'
    if isinstance(value, list):
        return '(\n' + ''.join(f'{indent}\t{encode(v, level + 1)},\n' for v in value) + indent + ')'
    return str(value) if isinstance(value, int) else json.dumps(str(value))


def read_project(path):
    if not path.exists():
        return {}
    return json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(path)]))['objects']


def generate(project=PROJECT):
    existing = read_project(project / 'project.pbxproj')
    objects = {}

    def add(key, isa, **fields):
        uid = hashlib.sha256(key.encode()).hexdigest()[:24].upper()
        assert uid not in objects, key
        objects[uid] = dict(isa=isa, **fields)
        return uid

    def configurations(key, settings):
        configs = []
        for name in ('Debug', 'Release'):
            values = dict(settings, GCC_OPTIMIZATION_LEVEL='0' if name == 'Debug' else '2',
                          DEBUG_INFORMATION_FORMAT='dwarf' if name == 'Debug' else 'dwarf-with-dsym',
                          ONLY_ACTIVE_ARCH='YES' if name == 'Debug' else 'NO')
            uid = add(key + '/' + name, 'XCBuildConfiguration', name=name, buildSettings=values)
            # Signing and version choices made in Xcode survive regeneration.
            for field, value in existing.get(uid, {}).get('buildSettings', {}).items():
                if field.startswith(('CODE_SIGN', 'DEVELOPMENT_TEAM', 'PROVISIONING_PROFILE')) or field in (
                        'PRODUCT_BUNDLE_IDENTIFIER', 'MARKETING_VERSION', 'CURRENT_PROJECT_VERSION'):
                    values[field] = value
            configs.append(uid)
        return add(key + '/configurations', 'XCConfigurationList', buildConfigurations=configs,
                   defaultConfigurationIsVisible=0, defaultConfigurationName='Debug')

    native = sorted((ROOT / 'ios/LuaRuntime').glob('*.m')) + [ROOT / name for name in (
        'src/uikit_module.m', 'src/plugins/git/Git.c', 'src/plugins/speech/Speech.m')]
    lua = [path for path in sorted((ROOT / 'vendor/lua-5.4.8/src').glob('*.c'))
           if path.name not in ('lua.c', 'luac.c')]
    source_refs, build_files = [], []
    for path in native + lua:
        relative = path.relative_to(ROOT).as_posix()
        ref = add(relative, 'PBXFileReference', name=path.name, path='../../' + relative,
                  sourceTree='SOURCE_ROOT', lastKnownFileType='sourcecode.c.objc' if path.suffix == '.m' else 'sourcecode.c.c')
        source_refs.append(ref)
        build_files.append(add('compile/' + relative, 'PBXBuildFile', fileRef=ref))

    browse = []
    for name, path in (('Application', '.'), ('Framework Lua', '../../lua'), ('Native bridge', '../../src')):
        browse.append(add('browse/' + name, 'PBXFileSystemSynchronizedRootGroup', name=name,
                          path=path, sourceTree='<group>'))
    browse.append(add('sources', 'PBXGroup', name='Compile Sources', children=source_refs, sourceTree='<group>'))
    assets = add('assets', 'PBXFileReference', path='Assets.xcassets', sourceTree='SOURCE_ROOT',
                 lastKnownFileType='folder.assetcatalog')

    def script(key, name, body, **fields):
        return add(key, 'PBXShellScriptBuildPhase', name=name, buildActionMask=2147483647,
                   shellPath='/bin/sh', shellScript='set -eu\n' + body,
                   runOnlyForDeploymentPostprocessing=0, **fields)

    header = script('header', 'Embed UIKit Lua API',
                    'mkdir -p "$DERIVED_FILE_DIR/generated"\n'
                    'xxd -i -n UIKit_lua "$LUA_OBJC_ROOT/lua/embedded/UIKit.lua" "$DERIVED_FILE_DIR/generated/UIKit.lua.h"\n',
                    inputPaths=['$(LUA_OBJC_ROOT)/lua/embedded/UIKit.lua'],
                    outputPaths=['$(DERIVED_FILE_DIR)/generated/UIKit.lua.h'])
    git = script('git', 'Build libgit2',
                 '/usr/bin/make -s -j"$(getconf _NPROCESSORS_ONLN)" -f "$LUA_OBJC_ROOT/scripts/libgit2/libgit2.mk" '
                 'SDK="$PLATFORM_NAME" ARCH=arm64 OUT="$DERIVED_FILE_DIR/libgit2"\n',
                 alwaysOutOfDate=1, outputPaths=['$(DERIVED_FILE_DIR)/libgit2/libgit2.a'])
    sources = add('compile', 'PBXSourcesBuildPhase', buildActionMask=2147483647, files=build_files,
                  runOnlyForDeploymentPostprocessing=0)
    resources = add('resources', 'PBXResourcesBuildPhase', buildActionMask=2147483647,
                    files=[add('icon', 'PBXBuildFile', fileRef=assets)], runOnlyForDeploymentPostprocessing=0)
    bundle = script('bundle', 'Bundle Lua and app assets',
                    'cd "$LUA_OBJC_ROOT"\npython3 scripts/ipad/xcode_bundle.py '
                    '--bundle "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"\n', alwaysOutOfDate=1)
    frameworks = ('UIKit', 'Foundation', 'CoreGraphics', 'CoreText', 'QuartzCore', 'Symbols',
                  'UserNotifications', 'Security', 'WebKit', 'SceneKit', 'GameController', 'AVFoundation', 'Speech')
    settings = dict(
        LUA_OBJC_ROOT='$(PROJECT_DIR)/../..', SDKROOT='iphoneos', ARCHS='arm64',
        SUPPORTED_PLATFORMS='iphoneos iphonesimulator', IPHONEOS_DEPLOYMENT_TARGET='26.5',
        TARGETED_DEVICE_FAMILY='1,2', SUPPORTS_MACCATALYST='NO',
        CLANG_ENABLE_OBJC_ARC='YES', ENABLE_USER_SCRIPT_SANDBOXING='NO',
        GCC_PREPROCESSOR_DEFINITIONS=['$(inherited)', 'LUA_USE_IOS'],
        HEADER_SEARCH_PATHS=['$(LUA_OBJC_ROOT)/' + path for path in (
            'ios/LuaRuntime', 'src', 'vendor/lua-5.4.8/src', 'vendor/libgit2/include')] + ['$(DERIVED_FILE_DIR)'],
        OTHER_LDFLAGS=['$(inherited)', '$(DERIVED_FILE_DIR)/libgit2/libgit2.a', '-lz'] +
                      [flag for framework in frameworks for flag in ('-framework', framework)],
        ALWAYS_SEARCH_USER_PATHS='NO', GCC_WARN_ABOUT_RETURN_TYPE='YES')
    root_configs = configurations('project', settings)
    target_configs = configurations('app', dict(
        PRODUCT_NAME='AdventureArena', PRODUCT_BUNDLE_IDENTIFIER='org.luaobjc.adventure-arena',
        INFOPLIST_FILE='Info.plist', GENERATE_INFOPLIST_FILE='NO',
        ASSETCATALOG_COMPILER_APPICON_NAME='AppIcon', MARKETING_VERSION='1.0', CURRENT_PROJECT_VERSION='1',
        CODE_SIGN_STYLE='Automatic', DEVELOPMENT_TEAM='BM2R8F5YHC'))
    product = add('product', 'PBXFileReference', path='AdventureArena.app', sourceTree='BUILT_PRODUCTS_DIR',
                  explicitFileType='wrapper.application')
    target = add('app', 'PBXNativeTarget', name='AdventureArena', productName='AdventureArena',
                 productReference=product, productType='com.apple.product-type.application',
                 buildConfigurationList=target_configs, buildPhases=[header, git, sources, resources, bundle],
                 buildRules=[], dependencies=[])
    products = add('products', 'PBXGroup', name='Products', children=[product], sourceTree='<group>')
    main = add('main', 'PBXGroup', children=browse + [assets, products], sourceTree='<group>')
    root = add('project', 'PBXProject', buildConfigurationList=root_configs, developmentRegion='en',
               knownRegions=['en', 'Base'], mainGroup=main, productRefGroup=products,
               projectDirPath='', projectRoot='', targets=[target], preferredProjectObjectVersion=77,
               attributes=existing.get(hashlib.sha256(b'project').hexdigest()[:24].upper(), {}).get(
                   'attributes', {'LastUpgradeCheck': '2700'}))
    write(project / 'project.pbxproj', '// !$*UTF8*$!\n' + encode(dict(
        archiveVersion=1, classes={}, objectVersion=77, objects=objects, rootObject=root)) + '\n')
    scheme_path = project / 'xcshareddata/xcschemes/AdventureArena.xcscheme'
    if not scheme_path.exists():
        scheme = ET.Element('Scheme', LastUpgradeVersion='2700', version='1.3')
        build = ET.SubElement(scheme, 'BuildAction', parallelizeBuildables='YES', buildImplicitDependencies='YES')
        entries = ET.SubElement(build, 'BuildActionEntries')
        entry = ET.SubElement(entries, 'BuildActionEntry', **{'buildFor' + action: 'YES' for action in (
            'Testing', 'Running', 'Profiling', 'Archiving', 'Analyzing')})
        reference = dict(BuildableIdentifier='primary', BlueprintIdentifier=target,
                         BuildableName='AdventureArena.app', BlueprintName='AdventureArena',
                         ReferencedContainer='container:AdventureArena.xcodeproj')
        ET.SubElement(entry, 'BuildableReference', **reference)
        for tag, config in (('LaunchAction', 'Debug'), ('ProfileAction', 'Release')):
            action = ET.SubElement(scheme, tag, buildConfiguration=config, useCustomWorkingDirectory='NO')
            if tag == 'LaunchAction':
                action.set('selectedDebuggerIdentifier', 'Xcode.DebuggerFoundation.Debugger.LLDB')
                action.set('selectedLauncherIdentifier', 'Xcode.IDEFoundation.Launcher.LLDB')
            runnable = ET.SubElement(action, 'BuildableProductRunnable', runnableDebuggingMode='0')
            ET.SubElement(runnable, 'BuildableReference', **reference)
        ET.SubElement(scheme, 'AnalyzeAction', buildConfiguration='Debug')
        ET.SubElement(scheme, 'ArchiveAction', buildConfiguration='Release', revealArchiveInOrganizer='YES')
        ET.indent(scheme)
        write(scheme_path, '<?xml version="1.0" encoding="UTF-8"?>\n' + ET.tostring(scheme, encoding='unicode') + '\n')
    # Like CMake's Xcode generator, supply shared workspace settings so Xcode
    # uses the generated scheme instead of automatically creating user schemes.
    settings_path = project / 'project.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings'
    workspace_settings = plistlib.loads(settings_path.read_bytes()) if settings_path.exists() else {}
    workspace_settings['IDEWorkspaceSharedSettings_AutocreateContextsIfNeeded'] = False
    write(settings_path, plistlib.dumps(workspace_settings).decode())
    return project


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', choices=['adventure-arena'])
    parser.parse_args()
    print(generate())
