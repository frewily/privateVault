#!/usr/bin/env python3
"""Overlay owned integration files onto the pinned, ignored source copy."""
import hashlib
import json
from pathlib import Path
import shutil

root = Path(__file__).resolve().parents[1]
source = root / '.tools/src/openlist-v4.2.8'
record = json.loads((source / '.privatevault-source.json').read_text())
if record['commit'] != '25e4eb663ffb73991a68d85df4f690d48ad137a6':
    raise SystemExit('Pinned source provenance mismatch')
owned = root / 'native/openlist_bridge'
files = {'privatevault/pvcore/pvcore.go': owned / 'pvcore.go'}
files['privatevault/pvcore/pvcore_test.go'] = owned / 'pvcore_test.go'
files['internal/op/privatevault_driver_allowlist.go'] = owned / 'overlay/op/privatevault_driver_allowlist.go'
for path in (owned / 'resources').rglob('*'):
    if path.is_file():
        files['public/dist/' + path.relative_to(owned / 'resources').as_posix()] = path
hashes = {}
previous = source / '.privatevault-overlay.json'
previous_hashes = json.loads(previous.read_text())['files'] if previous.exists() else {}
manifest = json.loads((root / 'toolchains/w01-android.json').read_text())
for name in ['go.mod', 'go.sum']:
    locked = manifest['go_modules']['locked'][name]
    origin = root / locked['path']
    actual = hashlib.sha256((source / name).read_bytes()).hexdigest()
    if actual not in {manifest['go_modules']['upstream_sha256'][name], locked['sha256']}:
        raise SystemExit(f'Unregistered module modification: {name}')
    if hashlib.sha256(origin.read_bytes()).hexdigest() != locked['sha256']:
        raise SystemExit(f'Module lock mismatch: {name}')
    files[name] = origin
    previous_hashes[name] = actual
for name, origin in files.items():
    target = source / name
    if target.exists():
        actual = hashlib.sha256(target.read_bytes()).hexdigest()
        if actual != previous_hashes.get(name):
            raise SystemExit(f'Unregistered source modification: {name}')
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(origin, target)
    hashes[name] = hashlib.sha256(origin.read_bytes()).hexdigest()
identity = hashlib.sha256(json.dumps(hashes, sort_keys=True).encode()).hexdigest()
previous.write_text(json.dumps({'build_id': 'pv-w01a-' + identity[:16], 'files': hashes,
                               'upstream_commit': record['commit']}, indent=2) + '\n')
record['upstream_modified'] = True
record['integration_overlay'] = '.privatevault-overlay.json'
(source / '.privatevault-source.json').write_text(json.dumps(record, indent=2) + '\n')
print('Staged pinned core overlay: pv-w01a-' + identity[:16])
