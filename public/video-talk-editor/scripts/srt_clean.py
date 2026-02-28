#!/usr/bin/env python3
"""Clean up SRT subtitles: remove filler words, merge short segments."""

import argparse
import re
import sys

def parse_srt(text):
    """Parse SRT into list of {index, start, end, text}."""
    blocks = re.split(r'\n\n+', text.strip())
    entries = []
    for block in blocks:
        lines = block.strip().split('\n')
        if len(lines) >= 3:
            try:
                idx = int(lines[0])
                times = lines[1]
                start, end = times.split(' --> ')
                text = '\n'.join(lines[2:])
                entries.append({'index': idx, 'start': start.strip(), 'end': end.strip(), 'text': text})
            except (ValueError, IndexError):
                continue
    return entries

def ts_to_seconds(ts):
    """HH:MM:SS,mmm -> seconds"""
    parts = ts.replace(',', '.').split(':')
    return float(parts[0]) * 3600 + float(parts[1]) * 60 + float(parts[2])

def seconds_to_ts(s):
    """seconds -> HH:MM:SS,mmm"""
    h = int(s // 3600)
    m = int((s % 3600) // 60)
    sec = int(s % 60)
    ms = int((s % 1) * 1000)
    return f"{h:02d}:{m:02d}:{sec:02d},{ms:03d}"

def main():
    parser = argparse.ArgumentParser(description="Clean SRT subtitles")
    parser.add_argument("srt_file", help="Input SRT file")
    parser.add_argument("--output", default=None, help="Output SRT path")
    parser.add_argument("--remove-filler", action="store_true", help="Remove filler words")
    parser.add_argument("--filler-words", default="嗯,啊,呃,那个,um,uh,like", help="Filler words to remove")
    parser.add_argument("--merge-short", type=float, default=0, help="Merge segments shorter than N seconds")
    args = parser.parse_args()

    with open(args.srt_file, "r", encoding="utf-8") as f:
        entries = parse_srt(f.read())

    print(f"Input: {len(entries)} subtitle entries")

    # Remove filler words
    if args.remove_filler:
        fillers = set(w.strip() for w in args.filler_words.split(","))
        cleaned = []
        removed = 0
        for e in entries:
            text = e["text"]
            for filler in fillers:
                text = re.sub(rf'\b{re.escape(filler)}\b', '', text, flags=re.IGNORECASE)
                text = re.sub(rf'{re.escape(filler)}', '', text)
            text = re.sub(r'\s+', ' ', text).strip()
            if text:
                e["text"] = text
                cleaned.append(e)
            else:
                removed += 1
        entries = cleaned
        print(f"  Removed {removed} filler-only entries")

    # Merge short segments
    if args.merge_short > 0 and len(entries) > 1:
        merged = [entries[0]]
        merge_count = 0
        for e in entries[1:]:
            prev = merged[-1]
            prev_dur = ts_to_seconds(prev["end"]) - ts_to_seconds(prev["start"])
            gap = ts_to_seconds(e["start"]) - ts_to_seconds(prev["end"])
            if prev_dur < args.merge_short and gap < 0.5:
                prev["end"] = e["end"]
                prev["text"] += " " + e["text"]
                merge_count += 1
            else:
                merged.append(e)
        entries = merged
        print(f"  Merged {merge_count} short segments")

    # Re-index
    for i, e in enumerate(entries, 1):
        e["index"] = i

    # Write output
    out_path = args.output or args.srt_file.replace(".srt", "_clean.srt")
    with open(out_path, "w", encoding="utf-8") as f:
        for e in entries:
            f.write(f"{e['index']}\n{e['start']} --> {e['end']}\n{e['text']}\n\n")

    print(f"Output: {out_path} ({len(entries)} entries)")

if __name__ == "__main__":
    main()
