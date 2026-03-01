#!/usr/bin/env python3
"""
Analyze transcription + video to produce a cut list.
Detects: silence, filler words, repeated phrases.
Outputs a JSON cut list with keep/remove segments.
"""

import argparse
import json
import subprocess
import re
import sys

DEFAULT_FILLER_ZH = "嗯,啊,呃,那个,就是,就是说,然后,对吧,其实,反正,怎么说呢,这个"
DEFAULT_FILLER_EN = "um,uh,like,you know,basically,actually,so,right,i mean,kind of,sort of"

def get_audio_silences(video_path, threshold_db=-35, min_duration=0.6):
    """Use ffmpeg silencedetect to find silence regions."""
    cmd = [
        "ffmpeg", "-i", video_path,
        "-af", f"silencedetect=noise={threshold_db}dB:d={min_duration}",
        "-f", "null", "-"
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
    stderr = result.stderr

    silences = []
    starts = re.findall(r"silence_start: ([\d.]+)", stderr)
    ends = re.findall(r"silence_end: ([\d.]+)", stderr)

    for i in range(min(len(starts), len(ends))):
        silences.append({
            "start": float(starts[i]),
            "end": float(ends[i]),
            "type": "silence",
        })

    return silences

def find_filler_words(words, filler_list, padding=0.12):
    """Find filler word segments from word-level timestamps."""
    fillers = []
    filler_set = set(f.lower().strip() for f in filler_list)

    for w in words:
        word_clean = w["word"].lower().strip().rstrip(",.!?。，！？")
        if word_clean in filler_set:
            fillers.append({
                "start": max(0, w["start"] - padding),
                "end": w["end"] + padding,
                "type": "filler",
                "word": w["word"],
            })

    return fillers

def merge_removals(removals, duration, padding=0.12):
    """Merge overlapping removal segments and compute keep segments."""
    if not removals:
        return [], [{"start": 0, "end": duration, "type": "keep"}]

    # Sort by start time
    removals.sort(key=lambda x: x["start"])

    # Merge overlapping
    merged = [removals[0].copy()]
    for r in removals[1:]:
        if r["start"] <= merged[-1]["end"] + 0.05:  # small gap tolerance
            merged[-1]["end"] = max(merged[-1]["end"], r["end"])
            if r["type"] != merged[-1]["type"]:
                merged[-1]["type"] = "mixed"
        else:
            merged.append(r.copy())

    # Clamp to valid range
    for m in merged:
        m["start"] = max(0, m["start"])
        m["end"] = min(duration, m["end"])

    # Build keep segments
    keeps = []
    cursor = 0
    for m in merged:
        if m["start"] > cursor + 0.05:
            keeps.append({"start": round(cursor, 3), "end": round(m["start"], 3), "type": "keep"})
        cursor = m["end"]
    if cursor < duration - 0.05:
        keeps.append({"start": round(cursor, 3), "end": round(duration, 3), "type": "keep"})

    return merged, keeps

def main():
    parser = argparse.ArgumentParser(description="Analyze transcription for smart cuts")
    parser.add_argument("json_file", help="Transcription JSON (word-level)")
    parser.add_argument("video_file", help="Input video file")
    parser.add_argument("--silence-thresh", type=float, default=-35, help="Silence threshold dB")
    parser.add_argument("--silence-min", type=float, default=0.6, help="Min silence duration (s)")
    parser.add_argument("--filler-words", default=None, help="Comma-separated filler words")
    parser.add_argument("--padding", type=float, default=0.12, help="Padding around speech (s)")
    parser.add_argument("--output", default=None, help="Output cut list JSON")
    args = parser.parse_args()

    # Load transcription
    with open(args.json_file, "r", encoding="utf-8") as f:
        transcript = json.load(f)

    duration = transcript["duration"]
    words = transcript.get("words", [])
    lang = transcript.get("language", "zh")

    print(f"Video duration: {duration:.1f}s | Language: {lang} | Words: {len(words)}")

    # Detect silences
    print("Detecting silences...")
    silences = get_audio_silences(args.video_file, args.silence_thresh, args.silence_min)
    print(f"  Found {len(silences)} silence regions")

    # Detect filler words (disabled by default, use --filler-words to enable)
    fillers = []
    if args.filler_words:
        filler_list = args.filler_words.split(",")
        print("Detecting filler words...")
        fillers = find_filler_words(words, filler_list, args.padding)
        print(f"  Found {len(fillers)} filler words")
    else:
        print("Filler word detection: skipped (silence-only mode)")

    # Combine removals
    all_removals = silences + fillers
    merged_removals, keep_segments = merge_removals(all_removals, duration, args.padding)

    # Calculate stats
    removed_time = sum(r["end"] - r["start"] for r in merged_removals)
    kept_time = sum(k["end"] - k["start"] for k in keep_segments)

    stats = {
        "original_duration": round(duration, 2),
        "edited_duration": round(kept_time, 2),
        "removed_duration": round(removed_time, 2),
        "removed_percent": round(removed_time / duration * 100, 1),
        "silence_regions": len(silences),
        "filler_words": len(fillers),
        "total_cuts": len(merged_removals),
        "total_segments": len(keep_segments),
    }

    # Output
    output = {
        "stats": stats,
        "keep": keep_segments,
        "remove": merged_removals,
    }

    out_path = args.output
    if not out_path:
        base = args.json_file.rsplit(".", 1)[0]
        out_path = f"{base}_cuts.json"

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, indent=2)

    print(f"\nCut plan saved: {out_path}")
    print(f"  Original: {stats['original_duration']}s")
    print(f"  Edited:   {stats['edited_duration']}s ({stats['removed_percent']}% removed)")
    print(f"  Cuts:     {stats['total_cuts']} ({stats['silence_regions']} silence + {stats['filler_words']} filler)")

if __name__ == "__main__":
    main()
