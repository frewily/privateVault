#!/usr/bin/env python3
"""Apply W01 additions to the generated, pinned Flutter Mac project."""
from pathlib import Path
import json
import plistlib

ROOT = Path(__file__).resolve().parents[1]
MAC = ROOT / 'apps/privatevault/macos'
project = MAC / 'Runner.xcodeproj/project.pbxproj'
text = project.read_text()
files = ['CoreTypes.swift', 'CoreController.swift', 'CoreBridge.swift']

def insert_before(anchor, addition):
    global text
    if text.count(anchor) != 1:
        raise SystemExit('Generated Xcode project differs from the pinned template.')
    text = text.replace(anchor, addition + anchor)

for index, name in enumerate(files, 1):
    ref = f'50560000000000000000000{index}'
    build = f'50560000000000000000010{index}'
    if f'{ref} /* {name} */ = ' in text:
        continue
    insert_before('/* End PBXBuildFile section */', f'\t\t{build} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref} /* {name} */; }};\n')
    insert_before('/* End PBXFileReference section */', f'\t\t{ref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = "<group>"; }};\n')
    anchor = '\t\t\t\t33CC10F02044A3C60003C045 /* AppDelegate.swift */,\n'
    insert_before(anchor, f'\t\t\t\t{ref} /* {name} */,\n')
    anchor = '\t\t\t\t33CC10F12044A3C60003C045 /* AppDelegate.swift in Sources */,\n'
    insert_before(anchor, f'\t\t\t\t{build} /* {name} in Sources */,\n')

phase = '505600000000000000000201'
if f'{phase} /* Stage PrivateVault Core */ = ' not in text:
    script = '/bin/zsh "$SRCROOT/../../../tools/prepare_core_macos.sh" "$TARGET_BUILD_DIR/$FULL_PRODUCT_NAME"\n'
    definition = f'''\t\t{phase} /* Stage PrivateVault Core */ = {{
\t\t\tisa = PBXShellScriptBuildPhase;
\t\t\talwaysOutOfDate = 1;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = ();
\t\t\tinputPaths = ();
\t\t\toutputPaths = ();
\t\t\tname = "Stage PrivateVault Core";
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t\tshellPath = /bin/sh;
\t\t\tshellScript = {json.dumps(script)};
\t\t}};
'''
    insert_before('/* End PBXShellScriptBuildPhase section */', definition)
    insert_before('\t\t\t\t3399D490228B24CF009A79C7 /* ShellScript */,\n', f'\t\t\t\t{phase} /* Stage PrivateVault Core */,\n')
    # Stage after Flutter embeds its frameworks/resources, before Xcode signs Runner.
    a = f'\t\t\t\t{phase} /* Stage PrivateVault Core */,\n'
    b = '\t\t\t\t3399D490228B24CF009A79C7 /* ShellScript */,\n'
    text = text.replace(a + b, b + a)

text = text.replace('path = "privatevault.app";', 'path = "PrivateVault W01.app";')
text = text.replace('/privatevault.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/privatevault', '/PrivateVault W01.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/PrivateVault W01')
text = text.replace('dev.privatevault.privatevault.RunnerTests', 'dev.privatevault.w01.RunnerTests')
text = text.replace('MACOSX_DEPLOYMENT_TARGET = 10.15;', 'MACOSX_DEPLOYMENT_TARGET = 12.0;')
project.write_text(text)

info = MAC / 'Runner/Configs/AppInfo.xcconfig'
body = info.read_text().replace('PRODUCT_NAME = privatevault', 'PRODUCT_NAME = PrivateVault W01').replace('PRODUCT_BUNDLE_IDENTIFIER = dev.privatevault.privatevault', 'PRODUCT_BUNDLE_IDENTIFIER = dev.privatevault.w01')
info.write_text(body)

for name in ['DebugProfile.entitlements', 'Release.entitlements']:
    path = MAC / 'Runner' / name
    data = plistlib.loads(path.read_bytes())
    assert data.get('com.apple.security.app-sandbox') is True
    data['com.apple.security.network.client'] = True
    data['com.apple.security.network.server'] = True
    path.write_bytes(plistlib.dumps(data))
path = MAC / 'Runner/Info.plist'
data = plistlib.loads(path.read_bytes())
data['NSAppTransportSecurity'] = {'NSAllowsLocalNetworking': True}
path.write_bytes(plistlib.dumps(data))
print('W01 Swift sources, private app identity, helper stage and local network permissions configured.')
