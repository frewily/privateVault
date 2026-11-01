#!/usr/bin/env python3
"""Inspect a signed arm64 W01 APK without installing or using adb."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]
SDK = Path.home() / 'Library/Android/sdk'
BUILD_TOOLS = SDK / 'build-tools/36.0.0'
NS = '{http://schemas.android.com/apk/res/android}'
PACKAGE = 'dev.privatevault.w01'
FIXTURE_SHA = 'd70a3c38d62588d9a2b61b7f676fef022039df34c12c92bfade0129103005901'


def run(args):
    environment = dict(os.environ)
    environment['JAVA_HOME'] = '/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home'
    return subprocess.check_output([str(x) for x in args], env=environment, text=True, stderr=subprocess.STDOUT)


def elf_alignment(data):
    if data[:6] != b'\x7fELF\x02\x01' or struct.unpack_from('<H', data, 18)[0] != 183:
        raise ValueError('APK contains a non-Android-arm64 native library')
    offset = struct.unpack_from('<Q', data, 32)[0]
    size, count = struct.unpack_from('<HH', data, 54)
    alignments = []
    for index in range(count):
        entry = offset + index * size
        if struct.unpack_from('<I', data, entry)[0] != 1:
            continue
        file_offset, address = struct.unpack_from('<QQ', data, entry + 8)
        alignment = struct.unpack_from('<Q', data, entry + 48)[0]
        if alignment < 16384 or (address - file_offset) % 16384:
            raise ValueError('ELF 16KB load alignment failed')
        alignments.append(alignment)
    if not alignments:
        raise ValueError('ELF has no load segments')
    return alignments


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('apk', nargs='?')
    parser.add_argument('--mode', choices=['release', 'debug'], default='release')
    parser.add_argument('--output-dir', type=Path, help='Separate inspection evidence directory')
    args = parser.parse_args()
    mode = args.mode
    apk = Path(args.apk or ROOT / f'apps/privatevault/build/android/app/outputs/apk/{mode}/app-{mode}.apk').resolve()
    if not apk.is_file():
        raise SystemExit('No actual APK exists; build success is required before inspection.')
    analyzer = SDK / 'cmdline-tools/22.0/bin/apkanalyzer'
    manifest_text = run([analyzer, 'manifest', 'print', apk])
    manifest = ET.fromstring(manifest_text)
    if manifest.get('package') != PACKAGE:
        raise ValueError('Unexpected application ID')
    sdk = manifest.find('uses-sdk')
    if sdk is None or sdk.get(NS + 'minSdkVersion') != '24' or sdk.get(NS + 'targetSdkVersion') != '36':
        raise ValueError('Unexpected minimum/target API')
    application = manifest.find('application')
    if application is None or application.get(NS + 'allowBackup') != 'false' or application.get(NS + 'usesCleartextTraffic') != 'false':
        raise ValueError('Application backup/cleartext boundary differs')
    debuggable = application.get(NS + 'debuggable', 'false') == 'true'
    extract_native = application.get(NS + 'extractNativeLibs', 'true') == 'true'
    if debuggable != (mode == 'debug') or extract_native != (mode == 'release') or application.get(NS + 'testOnly', 'false') != 'false':
        raise ValueError('Build mode or native extraction policy differs')
    if mode == 'release' and int(manifest.get(NS + 'versionCode', '0')) <= 1:
        raise ValueError('Owner update must advance the installed version code')
    services = [x for x in application.findall('service') if x.get(NS + 'name') in [PACKAGE + '.CoreService', '.CoreService']]
    if len(services) != 1 or services[0].get(NS + 'exported') != 'false' or services[0].get(NS + 'process') != ':pv_core':
        raise ValueError('Core service is not private and in its dedicated process')
    permissions = sorted(x.get(NS + 'name') for x in manifest.findall('uses-permission'))
    allowed = {'android.permission.INTERNET', PACKAGE + '.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION'}
    if not set(permissions).issubset(allowed) or 'android.permission.INTERNET' not in permissions:
        raise ValueError('Unexpected APK permissions: ' + repr(permissions))
    for item in manifest.findall('permission'):
        if item.get(NS + 'name') != PACKAGE + '.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION' or item.get(NS + 'protectionLevel') not in ['signature', '0x00000002', '0x2', '2']:
            raise ValueError('Unexpected app-defined permission')
    network_text = run([analyzer, 'resources', 'xml', '--file', '/res/xml/network_security_config.xml', apk])
    network = ET.fromstring(network_text)
    base = network.find('base-config')
    domains = network.findall('domain-config')
    if base is None or base.get('cleartextTrafficPermitted') != 'false' or len(domains) != 1:
        raise ValueError('Network base policy differs')
    hosts = domains[0].findall('domain')
    if domains[0].get('cleartextTrafficPermitted') != 'true' or len(hosts) != 1 or (hosts[0].text or '').strip() != '127.0.0.1' or hosts[0].get('includeSubdomains') != 'false':
        raise ValueError('Cleartext exception extends beyond exact loopback')
    extraction_text = run([analyzer, 'resources', 'xml', '--file', '/res/xml/data_extraction_rules.xml', apk])
    extraction = ET.fromstring(extraction_text)
    for kind in ['cloud-backup', 'device-transfer']:
        section = extraction.find(kind)
        if section is None or {(x.get('domain'), x.get('path')) for x in section.findall('exclude')} != {(x, '.') for x in ['root', 'file', 'database', 'sharedpref', 'external']}:
            raise ValueError('Test-secret backup exclusion differs')
    signature = run([BUILD_TOOLS / 'apksigner', 'verify', '--verbose', '--print-certs', apk])
    certificate = re.search(r'Signer #1 certificate SHA-256 digest: ([a-fA-F0-9]+)', signature)
    policy = json.loads((ROOT / 'toolchains/w01-android.json').read_text())
    expected_cert = policy['apk']['certificate_sha256']
    if hashlib.sha256((ROOT / '.local/w01-a/debug-cert.der').read_bytes()).hexdigest() != expected_cert:
        raise ValueError('Prepared certificate differs from the installed W01 baseline')
    if not certificate or certificate.group(1).lower() != expected_cert:
        raise ValueError('APK does not match the prepared independent debug certificate')
    run([BUILD_TOOLS / 'zipalign', '-c', '-P', '16', '4', apk])
    libraries = []
    overlay = json.loads((ROOT / '.tools/src/openlist-v4.2.8/.privatevault-overlay.json').read_text())
    with apk.open('rb') as source, zipfile.ZipFile(apk) as archive:
        names = [x for x in archive.namelist() if x.endswith('.so')]
        expected = {'lib/arm64-v8a/libflutter.so', 'lib/arm64-v8a/libgojni.so',
                    'lib/arm64-v8a/' + ('libapp.so' if mode == 'release' else 'libVkLayer_khronos_validation.so')}
        if set(names) != expected:
            raise ValueError('Unexpected native libraries/ABI: ' + repr(names))
        if mode == 'release' and any(x.endswith(('/kernel_blob.bin', '/vm_snapshot_data', '/isolate_snapshot_data')) for x in archive.namelist()):
            raise ValueError('Debug Dart payload found in release APK')
        fixture = archive.read('assets/flutter_assets/assets/w01_sample.png')
        if len(fixture) != 14415 or hashlib.sha256(fixture).hexdigest() != FIXTURE_SHA:
            raise ValueError('Bundled synthetic fixture mismatch')
        for name in names:
            info = archive.getinfo(name)
            expected_compression = zipfile.ZIP_DEFLATED if extract_native else zipfile.ZIP_STORED
            if info.compress_type != expected_compression:
                raise ValueError('Native library compression differs from installation policy')
            source.seek(info.header_offset)
            header = source.read(30)
            filename_size, extra_size = struct.unpack_from('<HH', header, 26)
            start = info.header_offset + 30 + filename_size + extra_size
            if not extract_native and start % 16384:
                raise ValueError('Native library ZIP data not 16KB aligned')
            data = archive.read(name)
            if name.endswith('/libgojni.so') and overlay['build_id'].encode() not in data:
                raise ValueError('APK embeds a stale Go core')
            libraries.append({'name': name, 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest(),
                              'compressed_bytes': info.compress_size, 'compression': 'deflate' if extract_native else 'stored',
                              'zip_data_offset': start, 'elf_load_alignments': elf_alignment(data)})
        largest_entries = [{'name': x.filename, 'bytes': x.file_size, 'compressed_bytes': x.compress_size}
                           for x in sorted(archive.infolist(), key=lambda x: x.compress_size, reverse=True)[:12]]
    jni_classes = []
    if mode == 'release':
        # Inspect the actual post-R8 DEX, not just the keep-rule source.
        with zipfile.ZipFile(ROOT / '.local/w01-a/openlist.aar') as aar:
            with zipfile.ZipFile(io.BytesIO(aar.read('classes.jar'))) as jar:
                classes = sorted(n[:-6].replace('/', '.') for n in jar.namelist() if n.endswith('.class'))
        required = {
            'dev.privatevault.nativebridge.pvcore.Pvcore': ['_init()V', 'buildID()Ljava/lang/String;', 'start(Ljava/lang/String;J)Ljava/lang/String;', 'stop()V', 'version()Ljava/lang/String;'],
            'go.Seq': ['setContext(Ljava/lang/Object;)V', 'incGoRef(ILgo/Seq$GoObject;)V', 'destroyRef(I)V'],
        }
        for name in classes:
            code = run([analyzer, 'dex', 'code', '--class', name, apk])
            descriptor = 'L' + name.replace('.', '/') + ';'
            if not re.search(r'^\.class .* ' + re.escape(descriptor) + r'$', code, re.M):
                raise ValueError('Generated JNI class removed/renamed: ' + name)
            signatures = re.findall(r'^\.method .* native (\S+)$', code, re.M)
            if not set(required.get(name, [])).issubset(signatures):
                raise ValueError('Generated JNI native entry removed/renamed: ' + name)
            jni_classes.append({'name': name, 'native_signatures': signatures})
    result = {'schema_version': 2, 'scope': 'APK static inspection only; no installation/device/JNI runtime test',
              'apk': str(apk), 'bytes': apk.stat().st_size, 'sha256': hashlib.sha256(apk.read_bytes()).hexdigest(),
              'package': PACKAGE, 'version_code': manifest.get(NS + 'versionCode'), 'version_name': manifest.get(NS + 'versionName'),
              'min_sdk': 24, 'target_sdk': 36, 'abi': 'arm64-v8a', 'permissions': permissions,
              'build_mode': mode, 'debuggable': debuggable, 'extract_native_libs': extract_native,
              'backup_and_device_transfer_exclusions_verified': True,
              'certificate_sha256': expected_cert, 'signature_verified': True, 'zipalign_16kb_command_passed': True,
              'native_zip_16kb_alignment': 'not required: compressed libraries extracted by Android' if extract_native else 'verified',
              'core_build_id': overlay['build_id'], 'native_libraries': libraries,
              'post_r8_jni_classes': jni_classes, 'largest_entries': largest_entries,
              'cleartext_exception': '127.0.0.1 only', 'core_service_exported': False, 'core_service_process': ':pv_core'}
    destination = args.output_dir or ROOT / ('.local/w01-a/apk-check-release' if mode == 'release' else '.local/w01-a/apk-check')
    destination.mkdir(parents=True, exist_ok=True)
    (destination / 'AndroidManifest.xml').write_text(manifest_text)
    (destination / 'network_security_config.xml').write_text(network_text)
    (destination / 'data_extraction_rules.xml').write_text(extraction_text)
    (destination / 'signature.txt').write_text(signature)
    (destination / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
