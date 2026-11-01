#!/usr/bin/env python3
"""One-shot, offline migration authorized by the owner on 2026-11-01.

Moves only PrivateVault-managed tools, merges public Pub packages without
overwriting existing versions, and retains originals until regression passes.
"""
from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
USER = Path.home()
STATE = ROOT / '.local/shared-toolchain-migration'
RECEIPT = STATE / 'receipt.json'
DEV = USER / 'Library/Developer'


def sha(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def fingerprint(path):
    if path.is_symlink():
        return ('link', os.readlink(path))
    if path.is_file():
        return ('file', sha(path))
    return tuple((p.relative_to(path).as_posix(), fingerprint(p))
                 for p in sorted(path.rglob('*')) if not p.is_dir() and p.name != '.DS_Store')


def allocated(path):
    return int(subprocess.check_output(['/usr/bin/du', '-sk', str(path)], text=True).split()[0]) * 1024


def main():
    if RECEIPT.exists():
        completed = json.loads(RECEIPT.read_text())
        if completed.get('status', '').startswith('complete'):
            print('Historical migration is complete. Existing global tools are preserved; do not replay installation.')
            return
        if sys.argv[1:] != ['--resume']:
            raise SystemExit('Migration receipt already exists; inspect before resuming.')
        record = json.loads(RECEIPT.read_text())
        for move in record['moves']:
            source = Path(move['source'])
            if source == ROOT / '.tools/gradle-home-w01-a/caches/modules-2':
                source = STATE / 'gradle-home-original/caches/modules-2'
            assert source.is_symlink() and source.resolve() == Path(move['shared'])
        # Resume finalization by verification only, never replay global writes.
        for name in ['go', 'gofmt', 'gradle', 'gomobile', 'gobind']:
            assert (USER / '.local/bin' / name).is_symlink()
        for name in ['.zprofile', '.zshrc']:
            assert (USER / name).read_text().count('# BEGIN shared-development-tools') == 1
        assert (USER / '.config/development-tools/env.zsh').is_file()
        record['global_shell_backups'] = [str(USER / '.config/development-tools/backups/20261101-privatevault' / name) for name in ['.zprofile', '.zshrc']]
        record['shared_flutter'] = str(DEV / 'flutter/3.47.8')
        record['shared_pub_cache'] = str(USER / '.pub-cache')
        record['gradle_readonly_dependency_seed'] = str(USER / 'Library/Caches/Gradle/dependency-seed')
        record['status'] = 'moved-and-linked; regression-and-cleanup-pending'
        RECEIPT.write_text(json.dumps(record, indent=2, ensure_ascii=False) + '\n')
        print(record['status'])
        return
    shared_flutter = DEV / 'flutter/3.47.8'
    metadata = json.loads((shared_flutter / 'bin/cache/flutter.version.json').read_text())
    assert metadata['frameworkRevision'] == '737ba8f885dc774b53b442759999a312c9461e4e'
    old_flutter = ROOT / '.tools/flutter'
    assert not old_flutter.is_symlink()
    assert not subprocess.check_output(['git', '-C', str(old_flutter), 'status', '--porcelain'])
    assert not subprocess.check_output(['git', '-C', str(shared_flutter), 'status', '--porcelain'])
    cache = ROOT / '.tools/pub-cache'
    packages = []
    # Preflight every collision before modifying either cache.
    for relative in ['hosted/pub.dev', 'hosted-hashes/pub.dev']:
        directory = cache / relative
        if not directory.exists():
            continue
        for source in sorted(directory.iterdir()):
            if source.name.startswith('.'):
                continue
            target = USER / '.pub-cache' / relative / source.name
            if target.exists() and fingerprint(source) != fingerprint(target):
                raise SystemExit('Public package conflict preserved: ' + source.name)
            packages.append((source, target))
    moves = [
        (ROOT / '.tools/go', DEV / 'go/1.27.3'),
        (ROOT / '.tools/go-bin', DEV / 'gomobile/197770444867'),
        (ROOT / '.tools/gradle-9.3.1', DEV / 'gradle/9.3.1'),
        (ROOT / '.tools/go-mod', USER / 'go/pkg/mod'),
        (ROOT / '.local/w01-a/go-build', USER / 'Library/Caches/go-build'),
        (ROOT / '.tools/gradle-home-w01-a/caches/modules-2', USER / 'Library/Caches/Gradle/dependency-seed/modules-2'),
    ]
    for source, target in moves:
        if not source.is_dir() or source.is_symlink() or target.exists() or target.is_symlink():
            raise SystemExit('Unexpected move state: ' + str(source) + ' -> ' + str(target))
    for name in ['go', 'gofmt', 'gradle', 'gomobile', 'gobind']:
        p = USER / '.local/bin' / name
        if p.exists() or p.is_symlink():
            raise SystemExit('Existing global command preserved: ' + name)
    for name in ['go/current', 'gradle/current', 'gomobile/current']:
        p = DEV / name
        if p.exists() or p.is_symlink():
            raise SystemExit('Existing default version preserved: ' + name)
    STATE.mkdir(parents=True, mode=0o700)
    record = {'date': '2026-11-01', 'network_downloaded': 0, 'status': 'migration-in-progress',
              'old_flutter_allocated_bytes': allocated(old_flutter), 'moves': [], 'public_pub_packages_moved': 0,
              'global_shell_backups': [], 'retained_until_validation': []}
    def save():
        RECEIPT.write_text(json.dumps(record, indent=2, ensure_ascii=False) + '\n')
    save()
    for source, target in packages:
        if not target.exists():
            target.parent.mkdir(parents=True, exist_ok=True)
            source.rename(target)
            record['public_pub_packages_moved'] += 1
    for source, target in moves:
        target.parent.mkdir(parents=True, exist_ok=True)
        source.rename(target)
        source.symlink_to(target, target_is_directory=True)
        record['moves'].append({'source': str(source), 'shared': str(target)})
        save()
    # Relocate old homes only as rollback material. Live Gradle settings stay ~/.gradle.
    for name, source in [('pub-cache-original', cache), ('gradle-home-original', ROOT / '.tools/gradle-home-w01-a'), ('flutter-3.47.5-original', old_flutter)]:
        backup = STATE / name
        source.rename(backup)
        record['retained_until_validation'].append(str(backup))
        save()
    cache.symlink_to(USER / '.pub-cache', target_is_directory=True)
    (ROOT / '.tools/gradle-home-w01-a').symlink_to(USER / '.gradle', target_is_directory=True)
    old_flutter.symlink_to(shared_flutter, target_is_directory=True)
    finish_global(record)


def finish_global(record):
    # Keep old alternate GOPATH paths working; future installs use the standard ~/go.
    previous_gopath = ROOT / '.tools/go-work'
    if previous_gopath.exists() and not previous_gopath.is_symlink():
        checkpoint = previous_gopath / 'pkg/sumdb'
        target = USER / 'go/pkg/sumdb'
        if checkpoint.exists():
            if target.exists():
                raise SystemExit('Existing Go checksum checkpoint preserved.')
            checkpoint.rename(target)
        for path in sorted(previous_gopath.rglob('*'), reverse=True):
            if path.is_dir():
                path.rmdir()
            else:
                raise SystemExit('Unreviewed old GOPATH file preserved.')
        previous_gopath.rmdir()
    if not previous_gopath.is_symlink():
        previous_gopath.symlink_to(USER / 'go', target_is_directory=True)
    for name, version in [('go', '1.27.3'), ('gradle', '9.3.1'), ('gomobile', '197770444867')]:
        (DEV / name / 'current').symlink_to(version, target_is_directory=True)
    for name, target in {
        'go': DEV / 'go/current/bin/go', 'gofmt': DEV / 'go/current/bin/gofmt',
        'gradle': DEV / 'gradle/current/bin/gradle',
        'gomobile': DEV / 'gomobile/current/gomobile', 'gobind': DEV / 'gomobile/current/gobind',
    }.items():
        (USER / '.local/bin' / name).symlink_to(target)
    config = USER / '.config/development-tools'
    backups = config / 'backups/20261101-privatevault'
    backups.mkdir(parents=True, mode=0o700, exist_ok=False)
    backups.chmod(0o700)
    env_file = config / 'env.zsh'
    if env_file.exists():
        raise SystemExit('Existing shared environment file preserved.')
    env_file.write_text('''# Shared developer commands; individual projects keep their own version pins.
typeset -U path PATH
path=("$HOME/.local/bin" "$HOME/go/bin" $path)
if [[ -d "$HOME/Library/Caches/Gradle/dependency-seed/modules-2" && -z "${GRADLE_RO_DEP_CACHE:-}" ]]; then
  export GRADLE_RO_DEP_CACHE="$HOME/Library/Caches/Gradle/dependency-seed"
fi
''')
    block = '\n# BEGIN shared-development-tools (2026-11-01)\n[[ -r "$HOME/.config/development-tools/env.zsh" ]] && source "$HOME/.config/development-tools/env.zsh"\n# END shared-development-tools\n'
    for name in ['.zprofile', '.zshrc']:
        file = USER / name
        before = file.read_bytes()
        if b'BEGIN shared-development-tools' in before:
            raise SystemExit('Existing managed shell block preserved.')
        backup = backups / name
        backup.write_bytes(before)
        backup.chmod(0o600)
        if file.read_bytes() != before:
            raise SystemExit('Shell file changed concurrently; preserved.')
        with file.open('ab') as output:
            output.write(block.encode())
        record['global_shell_backups'].append(str(backup))
    record['status'] = 'moved-and-linked; regression-and-cleanup-pending'
    record['shared_flutter'] = str(DEV / 'flutter/3.47.8')
    record['shared_pub_cache'] = str(USER / '.pub-cache')
    record['gradle_readonly_dependency_seed'] = str(USER / 'Library/Caches/Gradle/dependency-seed')
    RECEIPT.write_text(json.dumps(record, indent=2, ensure_ascii=False) + '\n')
    print(json.dumps({k: record[k] for k in ['status', 'public_pub_packages_moved', 'shared_flutter']}, ensure_ascii=False))


if __name__ == '__main__':
    main()
