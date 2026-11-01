#!/usr/bin/env python3
"""Fetch only pinned public inputs through the explicitly budgeted gateway."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import tarfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = json.loads((ROOT / 'toolchains/w01-android.json').read_text())


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest()


def download(opener, url, name, maximum, expected=None, exact=None):
    path = ROOT / '.tools/downloads/w01-a' / name
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        if (expected and digest(path) != expected) or (exact and path.stat().st_size != exact):
            raise ValueError(f'Existing input failed integrity check: {name}')
        return path
    temporary = path.with_suffix(path.suffix + '.partial')
    offset = temporary.stat().st_size if temporary.exists() else 0
    headers = {'Range': f'bytes={offset}-'} if offset else {}
    with opener.open(urllib.request.Request(url, headers=headers), timeout=45) as response:
        if offset and (response.status != 206 or not response.headers.get('Content-Range', '').startswith(f'bytes {offset}-')):
            raise ValueError('Server did not honor resume; existing partial input preserved')
        length = response.headers.get('Content-Length')
        if length is not None and offset + int(length) > maximum:
            raise ValueError(f'Input exceeds bounded size: {name}')
        with temporary.open('ab' if offset else 'wb') as output:
            while True:
                chunk = response.read(min(65536, maximum - output.tell() + 1))
                if not chunk:
                    break
                output.write(chunk)
                if output.tell() > maximum:
                    raise ValueError(f'Input exceeds bounded size: {name}')
    if exact is not None and temporary.stat().st_size != exact:
        raise ValueError(f'Incomplete input: {name}')
    if expected and digest(temporary) != expected:
        raise ValueError(f'SHA-256 mismatch: {name}')
    temporary.replace(path)
    print(json.dumps({'input': name, 'bytes': path.stat().st_size,
                      'sha256': digest(path)}), flush=True)
    return path


def install_go(opener):
    target = Path.home() / 'Library/Developer/go/1.27.3'
    if target.exists():
        if (target / 'VERSION').read_text().splitlines()[0] != MANIFEST['go']['version']:
            raise ValueError('Existing project Go differs from pinned version')
        return
    go = MANIFEST['go']
    archive = download(opener, go['url'], go['archive'], go['bytes'], go['sha256'], go['bytes'])
    pending = target.parent / 'go1.27.3.pending'
    if pending.exists():
        raise ValueError('Pending Go extraction exists; review before retrying')
    pending.mkdir(parents=True)
    with tarfile.open(archive, 'r:gz') as source:
        members = source.getmembers()
        if sum(x.size for x in members) > 512 * 1024**2:
            raise ValueError('Unexpected Go extraction size')
        for member in members:
            parts = PurePosixPath(member.name).parts
            if not parts or parts[0] != 'go' or '..' in parts or member.name.startswith('/') or not (member.isdir() or member.isfile()):
                raise ValueError('Unsafe Go archive entry')
        source.extractall(pending, members=members)
    (pending / 'go').rename(target)
    pending.rmdir()


def install_source(opener):
    commit = MANIFEST['openlist']['commit']
    target = ROOT / '.tools/src/openlist-v4.2.8'
    if target.exists():
        record = target / '.privatevault-source.json'
        if not record.exists() or json.loads(record.read_text())['commit'] != commit:
            raise ValueError('Existing core source has no matching provenance')
        return
    archive = download(opener, f'https://codeload.github.com/OpenListTeam/OpenList/zip/{commit}',
                       f'openlist-{commit}.zip', 32 * 1024**2)
    pending = target.with_name(target.name + '.pending')
    if pending.exists():
        raise ValueError('Pending source extraction exists; review before retrying')
    pending.mkdir(parents=True)
    with zipfile.ZipFile(archive) as source:
        members = source.infolist()
        if sum(x.file_size for x in members) > 256 * 1024**2:
            raise ValueError('Unexpected source extraction size')
        for member in members:
            path = PurePosixPath(member.filename)
            if path.is_absolute() or '..' in path.parts or not path.parts or path.parts[0] != f'OpenList-{commit}' or ((member.external_attr >> 16) & 0o170000) == 0o120000:
                raise ValueError('Unsafe source archive entry')
        source.extractall(pending)
    (pending / f'OpenList-{commit}').rename(target)
    pending.rmdir()
    (target / '.privatevault-source.json').write_text(json.dumps({
        'commit': commit, 'archive_sha256': digest(archive), 'upstream_modified': False,
    }, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('input', choices=['go', 'source', 'gradle'])
    parser.add_argument('--proxy', required=True)
    args = parser.parse_args()
    if not args.proxy.startswith('http://127.0.0.1:'):
        parser.error('An owner-budgeted loopback gateway is required')
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({'http': args.proxy, 'https': args.proxy}))
    if args.input == 'go':
        install_go(opener)
    elif args.input == 'source':
        install_source(opener)
    else:
        gradle = MANIFEST['gradle']
        shared = Path.home() / 'Library/Developer/gradle' / gradle['version']
        if (shared / 'bin/gradle').is_file() and (shared / 'lib' / f"gradle-daemon-main-{gradle['version']}.jar").is_file():
            print('Reusing pinned shared Gradle; no archive download.')
            return
        name = f"gradle-{gradle['version']}-bin.zip"
        download(opener, f'https://services.gradle.org/distributions/{name}', name,
                 gradle['bytes'], gradle['sha256'], gradle['bytes'])


if __name__ == '__main__':
    main()
