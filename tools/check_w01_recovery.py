#!/usr/bin/env python3
"""Force-quit only our native test host, then verify identity-based recovery."""
from pathlib import Path
import json
import os
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
host = ROOT / '.local/w01/native-check'
runtime = ROOT / '.local/w01/native-crash-recovery'
args = [str(host), str(ROOT / '.tools/core/v4.2.8/openlist'), str(runtime),
        str(ROOT / 'apps/privatevault/assets/w01_sample.png')]
process = subprocess.Popen([*args, 'hold'], stdout=subprocess.PIPE, text=True)
saved = None
try:
    line = process.stdout.readline()
    first = json.loads(line)
    assert first.get('passed') and first.get('phase') == 'ready'
    saved = json.loads((runtime / 'active.json').read_text())
    process.kill()
    process.wait(timeout=5)
    try:
        os.kill(saved['pid'], 0)
        core_alive_after_fault = True
    except ProcessLookupError:
        core_alive_after_fault = False
    # Same code and private root: the new host must prove ownership before signalling.
    recovery = subprocess.run([*args, 'smoke'], capture_output=True, text=True, timeout=45)
    rows = [json.loads(line) for line in recovery.stdout.splitlines() if line.startswith('{')]
    passed = recovery.returncode == 0 and rows and all(row.get('passed') for row in rows) and not (runtime / 'active.json').exists()
    print(json.dumps({'check': 'native_host_force_quit_recovery', 'passed': bool(passed),
                      'core_alive_after_fault': core_alive_after_fault,
                      'core_readback_verified': any(row.get('check') == 'authenticated_local_read' and row.get('passed') for row in rows)}))
    if not passed:
        print(json.dumps({'safe_results': rows}))
        raise SystemExit(1)
finally:
    if process.poll() is None:
        process.terminate()
        process.wait(timeout=10)
    # On failure retain the marker, never kill a process merely because a saved PID exists.
