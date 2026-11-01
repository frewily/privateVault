#!/usr/bin/env python3
"""Fault injection for this project's verified local development app only.

The app must first reach READY through its normal UI. This script does not
automate UI or read credentials; it validates the named test process and port.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'apps/privatevault/build/macos/Build/Products/Debug/PrivateVault W01.app'
RUNTIME = Path.home() / 'Library/Containers/dev.privatevault.w01/Data/Library/Application Support/PrivateVault-W01'

def executable(pid):
    return subprocess.check_output(['/bin/ps', '-p', str(pid), '-o', 'comm='], text=True).strip()

def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('target', choices=['core', 'app', 'orphan'])
    target = parser.parse_args().target
    marker = json.loads((RUNTIME / 'active.json').read_text())
    helper = APP / 'Contents/Helpers/openlist'
    assert marker['binary'] == str(helper)
    core_pid = marker['pid']
    assert core_pid > 1 and executable(core_pid) == str(helper)
    checksum = hashlib.sha256()
    with helper.open('rb') as stream:
        while block := stream.read(1024 * 1024):
            checksum.update(block)
    assert checksum.hexdigest() == marker['digest']
    sockets = subprocess.run(['/usr/sbin/lsof', '-nP', '-a', '-p', str(core_pid), '-iTCP', '-sTCP:LISTEN', '-Fn'], capture_output=True, text=True, check=True)
    assert [x for x in sockets.stdout.splitlines() if x.startswith('n')] == ['n127.0.0.1:' + str(marker['port'])]
    cwd = subprocess.check_output(['/usr/sbin/lsof', '-nP', '-a', '-p', str(core_pid), '-d', 'cwd', '-Fn'], text=True)
    assert [x for x in cwd.splitlines() if x.startswith('n')] == ['n' + marker['run']]
    app_pid = int(subprocess.check_output(['/bin/ps', '-p', str(core_pid), '-o', 'ppid='], text=True).strip())
    if target == 'orphan':
        assert app_pid == 1
        previous = json.loads((ROOT / '.local/w01/gui-app-fault.json').read_text())
        assert previous['target_exited'] is True and previous['only_verified_test_process_signalled'] is True
    else:
        if marker.get('supervised'):
            assert app_pid == marker['supervisor_pid']
            assert executable(app_pid) == str(APP / 'Contents/Helpers/core_supervisor')
            app_pid = int(subprocess.check_output(['/bin/ps', '-p', str(app_pid), '-o', 'ppid='], text=True).strip())
        assert app_pid > 1 and executable(app_pid) == str(APP / 'Contents/MacOS/PrivateVault W01')
    victim = core_pid if target == 'core' else app_pid
    if target == 'orphan': victim = core_pid
    os.kill(victim, signal.SIGTERM if target == 'orphan' else signal.SIGKILL)
    until = time.monotonic() + 6
    while alive(victim) and time.monotonic() < until:
        time.sleep(0.05)
    result = {'fault': target + '_unexpected_exit', 'only_verified_test_process_signalled': True,
              'target_exited': not alive(victim), 'core_alive_after_fault': alive(core_pid),
              'app_alive_after_fault': None if target == 'orphan' else alive(app_pid),
              'controlled_test_cleanup_only': target == 'orphan'}
    destination = ROOT / '.local/w01' / ('gui-' + target + '-fault.json')
    destination.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))

if __name__ == '__main__':
    main()
