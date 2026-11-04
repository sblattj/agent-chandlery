---
name: diagnosing-macos-disk-cpu-and-memory-usage
description: "Diagnose macOS disk space, CPU and memory use with bounded read-only scans. Use for what's using my CPU or RAM, high memory pressure, swap growth, large caches, or APFS sizes that differ from free space."
---

# Diagnose macOS resource use

Find which processes and directories account for current resource use. Read the system and requested paths; write diagnostic artifacts only. Cleanup and process termination require a separate user instruction.

## Do this

From this skill's directory:

```bash
python3 scripts/scan_macos_resource_usage.py --disk-root "$HOME"
```

Use an absolute helper path when running from another directory. Narrow `--disk-root` to the area the user asked about; repeat it for distinct roots. Use `--skip-disk` for CPU and memory only. The helper prints the artifact directory and progress, with a default 120-second command budget and 15 seconds per disk partition. `--out`, `--deadline-seconds`, `--per-root-seconds` and `--max-entries` override those limits. Root planning and enumeration check the deadline between filesystem operations; an individual metadata call can still wait on its filesystem.

Read `report.json` and the relevant raw command outputs. Tell the user which measurements completed, which are partial or unknown, and the largest observed contributors. If a large root times out, narrow the next scan to a specific child; retain the first result instead of repeating the same full traversal.

## Interpret the evidence

- **CPU:** use the second `top` sample for interval usage; a single initial sample can show misleading zeroes. Separate load average, total CPU use and individual process percentages. Use PID, parent PID, elapsed time and command arguments to identify a process family. A process above 100% can occupy multiple cores.
- **Memory:** start with memory pressure, compression and swap, then use `top`'s `MEM` values for process attribution. Do not sum RSS across processes and present it as physical RAM in use. Cached memory and swap allocation alone do not establish current pressure; report missing or inaccessible metrics.
- **Process ownership:** group related workers and compare their commands, parents and age before calling them orphaned. A long-running process or a missing parent is evidence to investigate, not authorization to stop it. Inspect specific PIDs with read-only process/open-file queries when attribution remains unclear; keep that follow-up bounded.
- **Disk:** distinguish logical file size, `du` allocation and filesystem free space. APFS clones share storage, so summed directory allocations and matching artifacts do not prove how many bytes deletion would free. Never add overlapping roots or parent and child totals together.
- **Coverage:** permission errors, deadlines and skipped symlinks remain visible. A measured subset is a lower-bound inventory, not the total size of all requested directories. Keep partial stdout and stderr; empty output from an interrupted command is unknown, not zero.

S-T: Busy CPU, full RAM and large folders are different measurements. Identify the owner of each before deciding whether anything should change.

## Why it's built this way

- Partition disk scans by immediate child so one dependency tree cannot hide every other result behind a timeout. Include hidden entries, stay on the filesystem and avoid traversing symlink children.
- Preserve raw output outside repositories. Process arguments and filenames may contain credentials or private data; sanitize any excerpt before sharing it. Never commit diagnostic artifacts with the skill.
- Stop at the configured deadline and report gaps. Do not install tools, start a model, kill processes, prune Git metadata, remove caches or apply system settings during diagnosis.

## Related

- `fixing-a-slow-git-or-zsh-shell-prompt`: investigate Git, fsmonitor and shell prompt latency after checking host resource pressure.
