#!/usr/bin/env python3
"""Collect bounded, read-only macOS resource evidence into private artifacts."""

import argparse
import datetime as dt
import json
import os
from pathlib import Path
import signal
import stat
import subprocess
import sys
import time
import uuid


def utc_now():
    return dt.datetime.now(dt.timezone.utc).isoformat()


def check_deadline(deadline):
    if deadline is not None and time.monotonic() >= deadline:
        raise TimeoutError("global deadline reached; remaining filesystem operations skipped")


def bounded_number(lower, upper, kind=float):
    def parse(value):
        try:
            number = kind(value)
        except ValueError:
            raise argparse.ArgumentTypeError("expected a number") from None
        if not lower <= number <= upper:
            raise argparse.ArgumentTypeError(f"must be between {lower} and {upper}")
        return number
    return parse


def private_file(path, mode="w"):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    return os.fdopen(fd, mode)


class Collector:
    def __init__(self, output, seconds):
        self.output = Path(output)
        self.output.mkdir(mode=0o700, parents=True, exist_ok=False)
        self.deadline = time.monotonic() + seconds
        self.log_file = private_file(self.output / "progress.log")
        self.report = {
            "started_at": utc_now(), "deadline_seconds": seconds,
            "deadline_at": (dt.datetime.now(dt.timezone.utc) + dt.timedelta(seconds=seconds)).isoformat(),
            "status": "running", "commands": [], "disk_roots": [],
            "notes": [
                "Raw process arguments and paths may contain secrets; sanitize before sharing.",
                "Use the SECOND top sample for interval CPU; retain MEM for process attribution.",
                "RSS is retained for attribution, not summed as physical memory usage.",
                "du reports allocated KiB, not unique or recoverable APFS space; clones and snapshots differ.",
                "Disk totals cover recorded child partitions, excluding root directory metadata and symlinks.",
                "Deadlines stop subprocesses and check enumeration; an in-flight Python filesystem call may finish later.",
            ],
        }
        self.save()
        self.log(f"Artifacts: {self.output}; deadline: {self.report['deadline_at']} ({seconds:g}s)")

    def log(self, message):
        line = f"{utc_now()} {message}"
        print(line, flush=True)
        self.log_file.write(line + "\n")
        self.log_file.flush()

    def save(self):
        temporary = self.output / ".report.next"
        with private_file(temporary) as stream:
            json.dump(self.report, stream, indent=2, ensure_ascii=True)
            stream.write("\n")
        temporary.replace(self.output / "report.json")

    def run(self, label, argv, timeout=15):
        index = len(self.report["commands"]) + 1
        prefix = f"{index:04d}-{label}"
        record = {"id": index, "label": label, "argv": argv, "status": "running",
                  "stdout": prefix + ".stdout", "stderr": prefix + ".stderr",
                  "started_at": utc_now()}
        self.report["commands"].append(record)
        budget = min(timeout, max(0, self.deadline - time.monotonic()))
        record["timeout_seconds"] = budget
        self.save()
        self.log(f"Command {index}: {label}; budget {budget:.2f}s")
        started = time.monotonic()
        process = None
        interrupted = False
        with private_file(self.output / record["stdout"], "wb") as stdout, private_file(self.output / record["stderr"], "wb") as stderr:
            try:
                if budget <= 0:
                    record["status"] = "not_run_deadline"
                else:
                    process = subprocess.Popen(argv, stdout=stdout, stderr=stderr, start_new_session=True)
                    record["pid"] = process.pid
                    self.save()
                    try:
                        process.wait(timeout=budget)
                        record["status"] = "complete" if process.returncode == 0 else "failed"
                    except subprocess.TimeoutExpired:
                        record["status"] = "timeout"
                    record["returncode"] = process.returncode
            except OSError as error:
                record.update(status="error", error=str(error))
            except KeyboardInterrupt:
                record["status"] = "interrupted"
                interrupted = True
            finally:
                if process is not None and (process.poll() is None or record["status"] == "timeout"):
                    # Only signal the session created for this command, including its children.
                    for sig in (signal.SIGTERM, signal.SIGKILL):
                        try:
                            os.killpg(process.pid, sig)
                        except ProcessLookupError:
                            pass
                        if sig == signal.SIGTERM:
                            try:
                                process.wait(timeout=0.2)
                            except subprocess.TimeoutExpired:
                                pass
                    process.wait(timeout=1)
                    record["returncode"] = process.returncode
        record["duration_seconds"] = round(time.monotonic() - started, 3)
        record["stdout_bytes"] = (self.output / record["stdout"]).stat().st_size
        record["stderr_bytes"] = (self.output / record["stderr"]).stat().st_size
        self.save()
        self.log(f"Command {index}: {record['status']}; stdout {record['stdout_bytes']}B, stderr {record['stderr_bytes']}B")
        if interrupted:
            raise KeyboardInterrupt
        return record


def plan_roots(requested, deadline=None):
    """Resolve aliases first, then keep only outermost requested roots."""
    roots = []
    for value in requested:
        item = {"requested_path": str(value)}
        try:
            check_deadline(deadline)
            path = Path(value).expanduser().resolve(strict=True)
            check_deadline(deadline)
            if not path.is_dir():
                raise ValueError("disk root must be a directory")
            item.update(path=str(path), status="planned")
        except (OSError, RuntimeError, ValueError) as error:
            item.update(status="unknown", error=str(error))
        roots.append(item)
    kept = set()
    for item in roots:
        if item["status"] != "planned":
            continue
        path = Path(item["path"])
        ancestor = next((other["path"] for other in roots if other["status"] == "planned"
                         and Path(other["path"]) in path.parents), None)
        if ancestor or str(path) in kept:
            item.update(status="excluded_overlap", covered_by=ancestor or str(path))
        else:
            kept.add(str(path))
    return roots


def scan_root(collector, root, limit, seconds):
    root.update(status="running", partitions=[], enumeration_complete=False,
                measured_partitions=0, reported_allocated_kib=None)
    collector.save()
    if time.monotonic() >= collector.deadline:
        root.update(status="unknown", error="global deadline reached before enumeration")
        return
    try:
        device = Path(root["path"]).stat().st_dev
        check_deadline(collector.deadline)
        with os.scandir(root["path"]) as entries:
            while True:
                check_deadline(collector.deadline)
                try:
                    entry = next(entries)
                except StopIteration:
                    root["enumeration_complete"] = True
                    break
                check_deadline(collector.deadline)
                if len(root["partitions"]) >= limit:
                    root["enumeration_error"] = f"max-entries {limit} reached; additional entries exist"
                    break
                row = {"path": entry.path, "status": "unknown"}
                root["partitions"].append(row)
                try:
                    check_deadline(collector.deadline)
                    info = entry.stat(follow_symlinks=False)
                    if stat.S_ISLNK(info.st_mode):
                        row["status"] = "excluded_symlink"
                    elif info.st_dev != device:
                        row["status"] = "excluded_mount"
                    else:
                        row["status"] = "planned"
                except OSError as error:
                    row.update(status="unknown", error=str(error))
                    if isinstance(error, TimeoutError):
                        raise
    except OSError as error:
        root["enumeration_error"] = str(error)
    root["entries_recorded"] = len(root["partitions"])
    collector.log(f"Disk root: {root['path']}; {root['entries_recorded']} children recorded; enumeration complete={root['enumeration_complete']}")
    for row in root["partitions"]:
        if row["status"] != "planned":
            continue
        if time.monotonic() >= collector.deadline:
            row.update(status="unknown", error="global deadline reached before measurement")
            continue
        record = collector.run("du", ["/usr/bin/du", "-P", "-x", "-k", "-s", "--", row["path"]], seconds)
        row["command_id"] = record["id"]
        row["status"] = "unknown"
        try:
            with (collector.output / record["stdout"]).open(errors="replace") as stream:
                size = int(stream.readline().split("\t", 1)[0])
            if size < 0:
                raise ValueError("negative size")
            row.update(allocated_kib=size, status="partial")
            if record["status"] == "complete" and record["stderr_bytes"] == 0:
                row["status"] = "complete"
        except (ValueError, OSError):
            row["error"] = "no usable du size; consult command stdout/stderr"
        collector.save()
    root["coverage"] = {status: sum(row["status"] == status for row in root["partitions"])
                        for status in ("complete", "partial", "unknown", "excluded_symlink", "excluded_mount")}
    measured = [row["allocated_kib"] for row in root["partitions"] if "allocated_kib" in row]
    root["measured_partitions"] = len(measured)
    if measured or (root["enumeration_complete"] and not root["partitions"]):
        root["reported_allocated_kib"] = sum(measured)
    root["status"] = "complete" if root["enumeration_complete"] and not any(root["coverage"][key] for key in ("partial", "unknown")) else "partial"
    collector.save()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--disk-root", action="append", help="Directory to partition into immediate children; repeatable, default HOME.")
    parser.add_argument("--out", type=Path, help="New artifact directory; default ~/.artifacts/macos-resource-usage/<UTC-unique>.")
    parser.add_argument("--deadline-seconds", type=bounded_number(0.1, 3600), default=120, help="Overall command deadline, 0.1..3600 (default 120).")
    parser.add_argument("--per-root-seconds", type=bounded_number(0.1, 300), default=15, help="Deadline per disk child partition, 0.1..300 (default 15).")
    parser.add_argument("--skip-disk", action="store_true", help="Collect only system/process evidence.")
    parser.add_argument("--max-entries", type=bounded_number(1, 10000, int), default=200, help="Maximum immediate children per disk root, 1..10000 (default 200).")
    args = parser.parse_args(argv)
    if sys.platform != "darwin":
        parser.error("this read-only collector requires macOS")
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    output = (args.out or Path.home() / ".artifacts" / "macos-resource-usage" / f"{stamp}-{uuid.uuid4().hex[:8]}").expanduser().absolute()
    try:
        collector = Collector(output, args.deadline_seconds)
    except OSError as error:
        parser.error(f"cannot create a new private artifact directory: {error}")
    commands = [
        ("hardware", ["/usr/sbin/sysctl", "hw.memsize", "hw.logicalcpu"]),
        ("vm-stat", ["/usr/bin/vm_stat"]),
        ("memory-pressure", ["/usr/bin/memory_pressure"]),
        ("swap", ["/usr/sbin/sysctl", "vm.swapusage"]),
        ("uptime", ["/usr/bin/uptime"]),
        ("filesystem", ["/bin/df", "-k"]),
        ("processes", ["/bin/ps", "-axo", "pid=,ppid=,%cpu=,rss=,etime=,command="]),
        ("top-cpu", ["/usr/bin/top", "-l", "2", "-s", "1", "-o", "cpu", "-n", "25", "-stats", "pid,command,cpu,mem"]),
        ("top-memory", ["/usr/bin/top", "-l", "2", "-s", "1", "-o", "mem", "-n", "25", "-stats", "pid,command,cpu,mem"]),
    ]
    try:
        for label, command in commands:
            collector.run(label, command)
        collector.report["disk_skipped"] = args.skip_disk
        if not args.skip_disk:
            collector.report["disk_roots"] = plan_roots(args.disk_root or [str(Path.home())], collector.deadline)
            for root in collector.report["disk_roots"]:
                if root["status"] == "planned":
                    scan_root(collector, root, args.max_entries, args.per_root_seconds)
        incomplete = any(command["status"] != "complete" for command in collector.report["commands"])
        incomplete |= any(root["status"] not in ("complete", "excluded_overlap") for root in collector.report["disk_roots"])
        collector.report["status"] = "partial" if incomplete else "complete"
    except KeyboardInterrupt:
        collector.report["status"] = "interrupted"
    except Exception as error:
        collector.report.update(status="error", error=str(error))
    finally:
        collector.report["finished_at"] = utc_now()
        collector.save()
        collector.log(f"Finished: {collector.report['status']}; report: {output / 'report.json'}")
        collector.log_file.close()
    return 0 if collector.report["status"] == "complete" else 1


if __name__ == "__main__":
    sys.exit(main())
