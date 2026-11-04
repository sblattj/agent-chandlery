"""Focused checks for resource collector boundaries; no live system scan."""

import contextlib
import io
import json
from pathlib import Path
import stat
import sys
import tempfile
import time
from types import SimpleNamespace
import unittest
from unittest.mock import MagicMock, Mock, patch

from scan_macos_resource_usage import Collector, plan_roots, scan_root


class CollectorBoundaries(unittest.TestCase):
    def test_timeout_retains_both_streams_and_terminates_command_children(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            marker = base / "child-survived"
            child = (
                "import pathlib, signal, sys, time; "
                "signal.signal(signal.SIGTERM, signal.SIG_IGN); "
                "time.sleep(0.9); pathlib.Path(sys.argv[1]).write_text('survived')"
            )
            parent = (
                "import signal, subprocess, sys, time; "
                "signal.signal(signal.SIGTERM, signal.SIG_IGN); "
                "subprocess.Popen([sys.executable, '-c', sys.argv[1], sys.argv[2]]); "
                "print('stdout before timeout', flush=True); "
                "print('stderr before timeout', file=sys.stderr, flush=True); time.sleep(30)"
            )
            with contextlib.redirect_stdout(io.StringIO()):
                collector = Collector(base / "artifacts", 0.3)
                started = time.monotonic()
                try:
                    result = collector.run("timeout-fixture", [sys.executable, "-c", parent, child, str(marker)], 5)
                    skipped = collector.run("after-deadline", [sys.executable, "-c", "raise SystemExit(99)"], 5)
                finally:
                    collector.log_file.close()
            self.assertLess(time.monotonic() - started, 2)
            self.assertEqual(result["status"], "timeout")
            self.assertLessEqual(result["timeout_seconds"], 0.3)
            self.assertIsNotNone(result["returncode"])
            self.assertEqual(skipped["status"], "not_run_deadline")
            self.assertNotIn("pid", skipped)
            self.assertEqual((collector.output / result["stdout"]).read_text(), "stdout before timeout\n")
            self.assertEqual((collector.output / result["stderr"]).read_text(), "stderr before timeout\n")
            saved = json.loads((collector.output / "report.json").read_text())
            self.assertEqual(saved["commands"][0]["status"], "timeout")
            self.assertEqual(stat.S_IMODE(collector.output.stat().st_mode), 0o700)
            for path in collector.output.iterdir():
                self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            time.sleep(1)
            self.assertFalse(marker.exists(), "a command child survived its process-group deadline")

    def test_aliases_and_overlapping_roots_have_one_measurement_owner(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            nested = base / "outer root" / "nested"
            nested.mkdir(parents=True)
            alias = base / "root alias"
            alias.symlink_to(nested.parent, target_is_directory=True)
            roots = plan_roots([str(nested), str(alias), str(nested.parent), str(base / "missing")])
            measured = [row for row in roots if row["status"] == "planned"]
            self.assertEqual(len(measured), 1)
            self.assertEqual(Path(measured[0]["path"]), nested.parent.resolve())
            self.assertEqual([row["status"] for row in roots], ["excluded_overlap", "planned", "excluded_overlap", "unknown"])
            self.assertIn("error", roots[-1])

    def test_expired_deadline_prevents_root_resolution_and_enumeration(self):
        expired = time.monotonic() - 1
        with patch.object(Path, "resolve") as resolve, patch.object(Path, "stat") as path_stat, patch("scan_macos_resource_usage.os.scandir") as scandir:
            roots = plan_roots(["unresolved root", "another root"], expired)
            collector = Mock(deadline=expired)
            root = {"path": "unread root"}
            scan_root(collector, root, 200, 3)
            resolve.assert_not_called()
            path_stat.assert_not_called()
            scandir.assert_not_called()
        self.assertEqual([row["status"] for row in roots], ["unknown", "unknown"])
        self.assertTrue(all("deadline" in row["error"] for row in roots))
        self.assertFalse(root["enumeration_complete"])
        self.assertIn("deadline", root["error"])

    def test_deadline_during_enumeration_prevents_next_fetch_or_stat(self):
        for expire_on_fetch in (True, False):
            with self.subTest(expire_on_fetch=expire_on_fetch):
                clock = [0]
                entry = Mock(path="unread child")
                iterator = MagicMock()
                iterator.__enter__.return_value = iterator

                def fetch():
                    if expire_on_fetch:
                        clock[0] = 10
                    return entry

                def entry_stat(**_kwargs):
                    clock[0] = 10
                    return SimpleNamespace(st_dev=1, st_mode=stat.S_IFREG)

                iterator.__next__.side_effect = fetch
                entry.stat.side_effect = entry_stat
                collector = Mock(deadline=10)
                root = {"path": "bounded root"}
                with patch("scan_macos_resource_usage.time.monotonic", side_effect=lambda: clock[0]), patch.object(Path, "stat", return_value=SimpleNamespace(st_dev=1)), patch("scan_macos_resource_usage.os.scandir", return_value=iterator):
                    scan_root(collector, root, 10000, 3)
                self.assertEqual(iterator.__next__.call_count, 1)
                self.assertEqual(entry.stat.call_count, 0 if expire_on_fetch else 1)
                self.assertFalse(root["enumeration_complete"])
                self.assertIn("deadline", root["enumeration_error"])
                collector.run.assert_not_called()

    def test_unknown_partition_is_distinct_from_measured_zero_and_empty_root(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            directory = base / "disk root"
            directory.mkdir()
            (directory / "empty file").touch()
            collector = Mock(deadline=time.monotonic() + 5, output=base)
            for stdout, status, expected_size, expected_count in (("", "timeout", None, 0), ("0\tchild\n", "complete", 0, 1)):
                with self.subTest(command_status=status):
                    (base / "du.stdout").write_text(stdout)
                    collector.run.return_value = {"id": 1, "stdout": "du.stdout", "status": status, "stderr_bytes": 0}
                    root = {"path": str(directory)}
                    scan_root(collector, root, 200, 3)
                    self.assertEqual(root["reported_allocated_kib"], expected_size)
                    self.assertEqual(root["measured_partitions"], expected_count)
            empty = base / "empty root"
            empty.mkdir()
            root = {"path": str(empty)}
            scan_root(collector, root, 200, 3)
            self.assertEqual(root["reported_allocated_kib"], 0)
            self.assertEqual(root["measured_partitions"], 0)
            self.assertTrue(root["enumeration_complete"])


if __name__ == "__main__":
    unittest.main()
