"""Regression checks for loopback fixture startup on isolated CI hosts."""

import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from Scripts.mock_model_server import FixtureServer


class FixtureServerTests(unittest.TestCase):
    def test_startup_does_not_require_reverse_dns(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch("socket.getfqdn", side_effect=RuntimeError("DNS is unavailable")):
                server = FixtureServer(("127.0.0.1", 0), Path(directory) / "requests.jsonl")
            try:
                self.assertEqual(server.server_address[0], "127.0.0.1")
                self.assertGreater(server.server_port, 0)
                self.assertEqual(server.server_port, server.server_address[1])
                self.assertEqual(server.server_name, "localhost")
            finally:
                server.server_close()


if __name__ == "__main__":
    unittest.main()
