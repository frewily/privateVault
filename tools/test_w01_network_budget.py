#!/usr/bin/env python3
"""Offline checks for the owner-approved transfer cap."""
import json
from pathlib import Path
import socket
import tempfile
import unittest

from w01_network_budget import Budget


class TransferBudgetTest(unittest.TestCase):
    def test_cap_is_shared_and_persisted_across_restarts(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'budget.json'
            budget = Budget(path, limit=5)
            producer, source = socket.socketpair()
            target, consumer = socket.socketpair()
            try:
                producer.sendall(b'123456789')
                self.assertTrue(budget.transfer(source, target, 'example.invalid'))
                self.assertEqual(consumer.recv(9), b'12345')
                self.assertEqual(budget.used, 5)
                with self.assertRaises(RuntimeError):
                    budget.transfer(source, target, 'example.invalid')
                with budget.lock:
                    budget.save_locked(force=True)
                resumed = Budget(path, limit=5)
                self.assertEqual(resumed.used, 5)
                self.assertEqual(resumed.hosts, {'example.invalid': 5})
                self.assertNotIn('12345', path.read_text())
                with self.assertRaises(ValueError):
                    Budget(path, limit=10)
            finally:
                for connection in (producer, source, target, consumer):
                    connection.close()


if __name__ == '__main__':
    unittest.main()
