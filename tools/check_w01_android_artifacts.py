#!/usr/bin/env python3
"""Check a real AAR, preserving the distinction from APK/device evidence."""
import hashlib
import json
from pathlib import Path
import struct
import zipfile

ROOT = Path(__file__).resolve().parents[1]
artifact = ROOT / '.local/w01-a/openlist.aar'
overlay = json.loads((ROOT / '.tools/src/openlist-v4.2.8/.privatevault-overlay.json').read_text())
with zipfile.ZipFile(artifact) as archive:
    libraries = [name for name in archive.namelist() if name.endswith('.so')]
    assert libraries == ['jni/arm64-v8a/libgojni.so'], 'Unexpected ABI/library set'
    library = archive.read(libraries[0])
    assert library[:6] == b'\x7fELF\x02\x01', 'Not ELF64 little-endian'
    assert struct.unpack_from('<H', library, 18)[0] == 183, 'Not AArch64'
    offset = struct.unpack_from('<Q', library, 32)[0]
    size, count = struct.unpack_from('<HH', library, 54)
    segments = []
    for index in range(count):
        entry = offset + index * size
        kind, _ = struct.unpack_from('<II', library, entry)
        if kind != 1:
            continue
        file_offset, virtual_address = struct.unpack_from('<QQ', library, entry + 8)
        alignment = struct.unpack_from('<Q', library, entry + 48)[0]
        assert alignment >= 16384 and (virtual_address - file_offset) % 16384 == 0, '16KB load alignment failed'
        segments.append(alignment)
    assert segments, 'No LOAD segments'
    assert overlay['build_id'].encode() in library, 'Stale core overlay'
    classes = ROOT / '.local/w01-a/aar-check/classes.jar'
    classes.parent.mkdir(parents=True, exist_ok=True)
    classes.write_bytes(archive.read('classes.jar'))
result = {
    'scope': 'AAR static only; no APK or Android runtime claim',
    'aar': '.local/w01-a/openlist.aar', 'bytes': artifact.stat().st_size,
    'sha256': hashlib.sha256(artifact.read_bytes()).hexdigest(),
    'build_id': overlay['build_id'], 'abi': 'arm64-v8a',
    'load_alignments': segments, 'elf_16kb_alignment_passed': True,
    'jni_sha256': hashlib.sha256(library).hexdigest(),
}
destination = ROOT / '.local/w01-a/aar-check/result.json'
destination.write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps(result, ensure_ascii=False))
