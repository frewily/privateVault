#!/usr/bin/env python3
"""Fetch pinned Google Maven artifacts with verified TLS and official SHA-1.

Fallback for the observed Java TLS failure, using the same official endpoint
and the cumulative-budget gateway. Only immutable Gradle content files are
seeded; Gradle's binary metadata/index databases are never edited.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
ITEMS = [('com.android', 'signflinger', '9.1.0'),
         ('com.android', 'zipflinger', '9.1.0'),
         ('com.android.tools', 'annotations', '32.1.0')]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--proxy', required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'http://127\.0\.0\.1:\d+', args.proxy):
        parser.error('An owner-budgeted loopback gateway is required')
    budget = json.loads((ROOT / '.local/w01-a/network-budget.json').read_text())
    if budget['accounted_bytes'] >= budget['limit_bytes']:
        raise SystemExit('Download allowance exhausted')
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({'https': args.proxy}))
    def get(url, maximum):
        with opener.open(url, timeout=30) as response:
            data = response.read(maximum + 1)
            if len(data) > maximum:
                raise ValueError('Artifact exceeds bounded size')
            return data
    records = []
    for group, artifact, version in ITEMS:
        name = f'{artifact}-{version}.jar'
        url = 'https://dl.google.com/dl/android/maven2/' + group.replace('.', '/') + f'/{artifact}/{version}/{name}'
        expected = get(url + '.sha1', 128).decode().strip()
        if not re.fullmatch(r'[a-f0-9]{40}', expected):
            raise ValueError('Official checksum format invalid')
        target = Path.home() / '.gradle/caches/modules-2/files-2.1' / group / artifact / version / expected / name
        if target.exists():
            data = target.read_bytes()
        else:
            data = get(url, 2 * 1024**2)
        if hashlib.sha1(data).hexdigest() != expected:
            raise ValueError('Artifact checksum mismatch')
        if not target.exists():
            target.parent.mkdir(parents=True, exist_ok=True)
            temporary = target.with_suffix('.pv-partial')
            with temporary.open('xb') as output:
                output.write(data)
            temporary.replace(target)
        records.append({'coordinate': f'{group}:{artifact}:{version}', 'url': url,
                        'bytes': len(data), 'sha1': expected, 'sha256': hashlib.sha256(data).hexdigest()})
    (ROOT / '.local/w01-a/google-maven-prefetch.json').write_text(json.dumps(records, indent=2) + '\n')
    print(json.dumps(records, indent=2))


if __name__ == '__main__':
    main()
