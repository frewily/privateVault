#!/usr/bin/env python3
"""Stage the pinned public core into this project's own development app only."""
from pathlib import Path
import argparse
import hashlib
import json
import plistlib
import shutil
import subprocess
import tarfile
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[1]
LOCK = json.loads((ROOT / 'toolchains/w01-macos.json').read_text())
CORE = ROOT / '.tools/core/v4.2.8/openlist'

def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        while block := stream.read(1024 * 1024):
            result.update(block)
    return result.hexdigest()

def prepare_source():
    if CORE.exists():
        if digest(CORE) != LOCK['openlist_source_binary_sha256']:
            raise SystemExit('Core checksum mismatch; refusing to execute or replace it.')
        return
    retained = Path('/private/tmp/privatevault-validation-20261026-Da3beZ/package/openlist-verified.tar.gz')
    archive = ROOT / '.tools/core/openlist-v4.2.8-darwin-arm64.tar.gz'
    archive.parent.mkdir(parents=True, exist_ok=True)
    if retained.is_file() and digest(retained) == LOCK['openlist_archive_sha256']:
        shutil.copyfile(retained, archive)
    elif not archive.is_file():
        url = 'https://github.com/OpenListTeam/OpenList/releases/download/v4.2.8/openlist-darwin-arm64.tar.gz'
        partial = archive.with_suffix('.partial')
        total = 0
        with urlopen(url, timeout=60) as response, partial.open('wb') as out:
            while block := response.read(min(1024 * 1024, 51573966 - total)):
                total += len(block)
                if total > 51573965:
                    raise SystemExit('Public archive exceeds the pinned size; download stopped.')
                out.write(block)
        if total != 51573965 or digest(partial) != LOCK['openlist_archive_sha256']:
            raise SystemExit('Downloaded archive verification failed; partial file retained.')
        partial.replace(archive)
    if archive.stat().st_size != 51573965 or digest(archive) != LOCK['openlist_archive_sha256']:
        raise SystemExit('Public archive checksum mismatch; nothing extracted.')
    CORE.parent.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive) as tf:
        for item in tf.getmembers():
            target = (CORE.parent / item.name).resolve()
            if not target.is_relative_to(CORE.parent.resolve()) or not (item.isfile() or item.isdir()):
                raise SystemExit('Unsafe archive member.')
        member = tf.getmember('openlist')
        if not member.isfile():
            raise SystemExit('Pinned archive does not contain a regular core file.')
        with tf.extractfile(member) as source, CORE.open('wb') as target:
            shutil.copyfileobj(source, target)
    CORE.chmod(0o755)
    if digest(CORE) != LOCK['openlist_source_binary_sha256']:
        raise SystemExit('Extracted core checksum mismatch.')

def stage(app):
    app = app.resolve()
    if not app.is_relative_to((ROOT / 'apps/privatevault/build').resolve()) or app.suffix != '.app':
        raise SystemExit('Only this project\'s built development app may be staged.')
    with (app / 'Contents/Info.plist').open('rb') as stream:
        if plistlib.load(stream).get('CFBundleIdentifier') != LOCK['bundle_id']:
            raise SystemExit('Unrecognized app identity; refusing to sign it.')
    if not CORE.is_file() or digest(CORE) != LOCK['openlist_source_binary_sha256']:
        raise SystemExit('Pinned public core missing or modified; run --prepare-source first.')
    fixture = ROOT / 'apps/privatevault/assets/w01_sample.png'
    if digest(fixture) != LOCK['fixture_sha256']:
        raise SystemExit('Fixture checksum mismatch.')
    helpers = app / 'Contents/Helpers'
    resources = app / 'Contents/Resources'
    helpers.mkdir(exist_ok=True)
    resources.mkdir(exist_ok=True)
    helper = helpers / 'openlist'
    shutil.copyfile(CORE, helper)
    helper.chmod(0o755)
    subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', '--entitlements',
                    str(ROOT / 'tools/core_helper.entitlements'), str(helper)], check=True)
    supervisor = helpers / 'core_supervisor'
    subprocess.run(['/usr/bin/xcrun', '--sdk', 'macosx', 'swiftc', '-parse-as-library', '-swift-version', '5',
                    '-target', 'arm64-apple-macosx12.0',
                    str(ROOT / 'apps/privatevault/macos/Helpers/CoreSupervisor.swift'), '-o', str(supervisor)], check=True)
    subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', '--entitlements',
                    str(ROOT / 'tools/core_helper.entitlements'), str(supervisor)], check=True)
    shutil.copyfile(fixture, resources / 'w01_sample.png')
    manifest = {'version': LOCK['openlist_version'], 'source_sha256': LOCK['openlist_source_binary_sha256'],
                'runtime_sha256': digest(helper), 'fixture_sha256': LOCK['fixture_sha256'],
                'supervisor_sha256': digest(supervisor)}
    (resources / 'core_manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print('Pinned core staged into the private development app; original core unchanged.')

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--prepare-source', action='store_true')
    parser.add_argument('app', nargs='?')
    args = parser.parse_args()
    if args.prepare_source:
        prepare_source()
        print('Pinned public core source verified.')
    elif args.app:
        stage(Path(args.app))
    else:
        parser.error('Choose --prepare-source or an app bundle path.')
