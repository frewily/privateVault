#!/usr/bin/env python3
"""Project-local HTTPS CONNECT gateway for public build downloads.

Counts encrypted upstream traffic, including requests. Uses explicitly recorded
additive owner grants and preserves a 64 MiB reserve across restarts.
No URLs, credentials, headers, or response bodies enter the ledger.
"""
import argparse
import fcntl
import json
import os
from pathlib import Path
import selectors
import socket
import socketserver
import threading
import time
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
LEDGER = ROOT / '.local/w01-a/network-budget.json'
POLICY = json.loads((ROOT / 'toolchains/w01-android.json').read_text())['network']
LIMIT = POLICY['gateway_limit_bytes']
HOSTS = {
    'go.dev', 'dl.google.com', 'proxy.golang.org', 'sum.golang.org',
    'storage.googleapis.com', 'github.com', 'api.github.com',
    'codeload.github.com', 'raw.githubusercontent.com',
    'release-assets.githubusercontent.com', 'objects.githubusercontent.com',
    'services.gradle.org', 'downloads.gradle.org', 'plugins.gradle.org',
    'plugins-artifacts.gradle.org', 'repo.maven.apache.org', 'repo1.maven.org',
    'maven.google.com', 'pub.dev',
}


class Budget:
    def __init__(self, path=LEDGER, limit=LIMIT):
        self.path, self.limit = path, limit
        self.lock = threading.Lock()
        self.used = 0
        self.hosts = {}
        self.grants = POLICY.get('grants', [])
        self.previous_ledger_sha256 = None
        self.last_saved = 0
        if path.exists():
            data = json.loads(path.read_text())
            if data['limit_bytes'] != limit:
                raise ValueError('Existing transfer limit differs; explicit review required')
            if data.get('grants', self.grants) != self.grants:
                raise ValueError('Transfer grant history differs; explicit review required')
            self.used, self.hosts = data['accounted_bytes'], data['hosts']
            self.previous_ledger_sha256 = data.get('previous_ledger_sha256')

    def transfer(self, source, target, host):
        # Sockets are nonblocking; do not reserve bytes for a blocked read.
        with self.lock:
            left = self.limit - self.used
            if left <= 0:
                raise RuntimeError('Download allowance exhausted')
            try:
                data = source.recv(min(left, 32768))
            except BlockingIOError:
                return True
            if not data:
                return False
            self.used += len(data)
            self.hosts[host] = self.hosts.get(host, 0) + len(data)
            self.save_locked()
        view = memoryview(data)
        while view:
            try:
                sent = target.send(view)
                if sent == 0:
                    return False
                view = view[sent:]
            except BlockingIOError:
                time.sleep(.005)
        return True

    def save_locked(self, force=False):
        if not force and self.used - self.last_saved < 1024 * 1024:
            return
        self.path.parent.mkdir(parents=True, exist_ok=True)
        data = {'schema_version': 1, 'limit_bytes': self.limit,
                'owner_allowance_bytes': POLICY['owner_allowance_bytes'], 'accounted_bytes': self.used,
                'measurement': 'upstream encrypted received and sent bytes; 64MiB reserve',
                'hosts': self.hosts, 'grants': self.grants,
                'previous_ledger_sha256': self.previous_ledger_sha256}
        temp = self.path.with_suffix('.tmp')
        temp.write_text(json.dumps(data, indent=2) + '\n')
        temp.replace(self.path)
        self.last_saved = self.used


class Gateway(socketserver.StreamRequestHandler):
    def handle(self):
        upstream = None
        try:
            line = self.rfile.readline(2049).decode('ascii').strip()
            parts = line.split()
            if len(parts) != 3 or parts[0] != 'CONNECT':
                self.wfile.write(b'HTTP/1.1 405 Method Not Allowed\r\n\r\n')
                return
            host, port = parts[1].rsplit(':', 1)
            if host not in HOSTS or port != '443':
                self.wfile.write(b'HTTP/1.1 403 Forbidden\r\n\r\n')
                return
            for _ in range(64):
                header = self.rfile.readline(8193)
                if header in (b'\r\n', b'\n'):
                    break
                if len(header) > 8192 or not header:
                    return
            else:
                return
            with self.server.budget.lock:
                if self.server.budget.used >= self.server.budget.limit:
                    self.wfile.write(b'HTTP/1.1 503 Allowance Exhausted\r\n\r\n')
                    return
            route = self.server.upstream_proxy
            if route:
                upstream = socket.create_connection(route, timeout=20)
                upstream.sendall(f'CONNECT {host}:443 HTTP/1.1\r\nHost: {host}:443\r\n\r\n'.encode('ascii'))
                response = bytearray()
                while not response.endswith(b'\r\n\r\n') and len(response) < 8192:
                    part = upstream.recv(1)
                    if not part:
                        return
                    response.extend(part)
                if not response.startswith((b'HTTP/1.1 200 ', b'HTTP/1.0 200 ')):
                    return
            else:
                upstream = socket.create_connection((host, 443), timeout=20)
            upstream.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 262144)
            self.wfile.write(b'HTTP/1.1 200 Connection Established\r\n\r\n')
            self.wfile.flush()
            upstream.setblocking(False)
            self.connection.setblocking(False)
            with selectors.DefaultSelector() as selector:
                selector.register(upstream, selectors.EVENT_READ, self.connection)
                selector.register(self.connection, selectors.EVENT_READ, upstream)
                while True:
                    events = selector.select(timeout=30)
                    if not events:
                        return
                    for key, _ in events:
                        if not self.server.budget.transfer(key.fileobj, key.data, host):
                            return
        except (OSError, ValueError, RuntimeError):
            pass
        finally:
            if upstream is not None:
                upstream.close()


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = False
    daemon_threads = True
    request_queue_size = 16


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=0)
    args = parser.parse_args()
    LEDGER.parent.mkdir(parents=True, exist_ok=True)
    ownership = LEDGER.with_suffix('.lock').open('a')
    fcntl.flock(ownership, fcntl.LOCK_EX | fcntl.LOCK_NB)
    budget = Budget()
    configured = urllib.request.getproxies().get('https')
    route = None
    if configured:
        parsed = urllib.parse.urlsplit(configured)
        if parsed.scheme != 'http' or parsed.hostname != '127.0.0.1' or parsed.username or parsed.password:
            raise ValueError('Existing proxy route needs explicit review')
        route = (parsed.hostname, parsed.port or 80)
    with Server(('127.0.0.1', args.port), Gateway) as server:
        server.budget = budget
        server.upstream_proxy = route
        with budget.lock:
            budget.save_locked(force=True)
        print(json.dumps({'proxy': f'http://127.0.0.1:{server.server_address[1]}',
                          'remaining_bytes': budget.limit - budget.used,
                          'pid': os.getpid()}), flush=True)
        try:
            server.serve_forever(poll_interval=.2)
        except KeyboardInterrupt:
            pass
        finally:
            with budget.lock:
                budget.save_locked(force=True)


if __name__ == '__main__':
    main()
