#!/usr/bin/env python3
"""Fails CI when the physics of the scripted showcase gets too slow.

Run:  godot --headless --path . -- --mode=showcase --seed=1 --prof --quality=medium \\
        | python3 tools/perf_gate.py --max-busy-ms 12

It reads the PROF lines the director prints once a second (mean and worst
physics step, measured by PhysicsClock: engine and scripts together) and
averages the busy seconds, the ones with at least 30 pieces moving. The
limit is loose on purpose: CI runners are noisy, the gate is there to catch
big regressions, not 10%.
"""
import argparse
import os
import re
import sys

PROF = re.compile(r"PROF physics ([\d.]+) ms/step \(worst ([\d.]+)\)  pieces (\d+) \(awake (\d+)\)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--max-busy-ms", type=float, default=12.0)
    ap.add_argument("--min-busy-seconds", type=int, default=5)
    args = ap.parse_args()

    secs = []
    done = ""
    errors = []
    for line in sys.stdin:
        sys.stdout.write(line)
        m = PROF.search(line)
        if m:
            secs.append((float(m[1]), float(m[2]), int(m[3]), int(m[4])))
        if line.startswith("SHOWCASE_DONE"):
            done = line.strip()
        if "SCRIPT ERROR" in line or line.startswith("ERROR"):
            errors.append(line.strip())

    busy = [s for s in secs if s[3] >= 30]
    mean = sum(s[0] for s in busy) / max(len(busy), 1)
    peak = max((s[0] for s in secs), default=0.0)
    worst = max((s[1] for s in secs), default=0.0)
    pieces = max((s[2] for s in secs), default=0)
    report = (
        f"seconds {len(secs)}, busy {len(busy)} | busy mean {mean:.1f} ms/step, "
        f"worst second {peak:.1f}, worst step {worst:.1f} | max pieces {pieces}"
    )
    print("PERF " + report)

    failures = []
    if not done:
        failures.append("the showcase did not finish")
    if errors:
        failures.append(f"{len(errors)} errors")
    if len(busy) < args.min_busy_seconds:
        failures.append(f"only {len(busy)} busy seconds: the showcase broke less than expected")
    if mean > args.max_busy_ms:
        failures.append(f"busy mean {mean:.1f} ms/step is over the {args.max_busy_ms:.1f} ms limit")

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as f:
            f.write("### Physics perf gate (showcase, headless)\n\n")
            f.write(f"`{report}`\n\n{done}\n\n")
            f.write(("**FAIL**: " + "; ".join(failures)) if failures else "Within limits.")
            f.write("\n")
    for msg in failures:
        print(f"::error::{msg}")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
