#!/usr/bin/env python3
"""Preview cut list in human-readable format."""

import argparse
import json
import sys

def format_time(seconds):
    m = int(seconds // 60)
    s = seconds % 60
    return f"{m:02d}:{s:05.2f}"

def main():
    parser = argparse.ArgumentParser(description="Preview cut plan")
    parser.add_argument("cuts_json", help="Cut list JSON file")
    args = parser.parse_args()

    with open(args.cuts_json, "r", encoding="utf-8") as f:
        data = json.load(f)

    stats = data["stats"]
    keeps = data["keep"]
    removes = data["remove"]

    print("=" * 60)
    print("  CUT PREVIEW")
    print("=" * 60)
    print(f"  Original duration: {stats['original_duration']}s")
    print(f"  After editing:     {stats['edited_duration']}s")
    print(f"  Removed:           {stats['removed_duration']}s ({stats['removed_percent']}%)")
    print(f"  Total cuts:        {stats['total_cuts']}")
    print("=" * 60)

    # Merge keeps and removes into timeline
    timeline = []
    for k in keeps:
        timeline.append({**k, "action": "KEEP"})
    for r in removes:
        timeline.append({**r, "action": "CUT"})
    timeline.sort(key=lambda x: x["start"])

    print(f"\n{'Time':>14}  {'Duration':>8}  {'Action':<6}  {'Reason'}")
    print("-" * 60)

    for item in timeline:
        start = format_time(item["start"])
        end = format_time(item["end"])
        dur = item["end"] - item["start"]
        action = item["action"]
        reason = item.get("type", "")
        word = item.get("word", "")

        marker = ">>>" if action == "KEEP" else "  x"
        extra = f" [{word}]" if word else ""

        print(f"  {start}-{end}  {dur:6.2f}s  {marker} {action:<6} {reason}{extra}")

    print("-" * 60)
    print(f"\n  {len(keeps)} segments kept, {len(removes)} segments cut")
    print()

if __name__ == "__main__":
    main()
