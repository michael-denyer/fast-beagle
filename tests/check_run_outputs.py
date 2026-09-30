#!/usr/bin/env python3
"""Check output ownership through process exit and observable file contents."""

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIXTURE = Path(sys.argv.pop(1)).resolve() if len(sys.argv) > 1 else ROOT / "build/output/run_outputs_fixture"


class RunOutputs(unittest.TestCase):
    def check_mode(self, mode, expected_exit, complete):
        with tempfile.TemporaryDirectory() as tmp:
            prefix = Path(tmp) / "result"
            sample = Path(str(prefix) + ".sample")
            sample.write_text("untouched sample\n")
            proc = subprocess.run(
                [str(FIXTURE), mode, str(prefix)], capture_output=True, text=True, timeout=30, check=False
            )
            self.assertEqual(proc.returncode, expected_exit, proc.stderr)
            self.assertEqual(proc.stderr, "fixture failure\n" if expected_exit else "")
            if complete:
                self.assertEqual(Path(str(prefix) + ".bgen").read_text(), "data after reader error\n")
                self.assertEqual(Path(str(prefix) + ".info").read_text(), "info\n")
                self.assertEqual(sample.read_text(), "sample\n")
            else:
                self.assertFalse(Path(str(prefix) + ".bgen").exists())
                self.assertFalse(Path(str(prefix) + ".info").exists())
                self.assertEqual(sample.read_text(), "untouched sample\n")

    def test_closed_partial_members_are_removed(self):
        self.check_mode("partial", 1, False)

    def test_completed_members_survive_later_failure(self):
        self.check_mode("complete", 1, True)

    def test_caught_reader_error_leaves_outputs_writable(self):
        self.check_mode("caught", 0, True)

    def test_normal_free_disarms_exit_cleanup(self):
        self.check_mode("normal", 0, True)

    def test_terminal_cleanup_refuses_concurrent_late_open(self):
        self.check_mode("abort", 1, False)


if __name__ == "__main__":
    unittest.main()
