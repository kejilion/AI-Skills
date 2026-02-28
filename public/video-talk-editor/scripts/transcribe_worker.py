#!/usr/bin/env python3
"""Transcribe video/audio to SRT + word-level JSON using faster-whisper."""

import argparse
import json
import sys
import os

def format_ts(seconds):
    """Format seconds to SRT timestamp HH:MM:SS,mmm"""
    h = int(seconds // 3600)
    m = int((seconds % 3600) // 60)
    s = int(seconds % 60)
    ms = int((seconds % 1) * 1000)
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"

def main():
    parser = argparse.ArgumentParser(description="Transcribe video to SRT+JSON")
    parser.add_argument("input", help="Input video/audio file")
    parser.add_argument("--lang", default="auto", help="Language: zh, en, auto")
    parser.add_argument("--model", default="large-v3", help="Whisper model size")
    parser.add_argument("--output-srt", required=True, help="Output SRT path")
    parser.add_argument("--output-json", required=True, help="Output JSON path")
    parser.add_argument("--device", default="auto", help="Device: auto, cpu, cuda")
    args = parser.parse_args()

    from faster_whisper import WhisperModel

    # Device selection
    device = args.device
    if device == "auto":
        try:
            import torch
            device = "cuda" if torch.cuda.is_available() else "cpu"
        except ImportError:
            device = "cpu"

    compute_type = "float16" if device == "cuda" else "int8"

    print(f"Loading model: {args.model} (device={device}, compute={compute_type})")
    model = WhisperModel(args.model, device=device, compute_type=compute_type)

    # Transcribe
    lang = None if args.lang == "auto" else args.lang
    print(f"Transcribing: {args.input}")

    segments_gen, info = model.transcribe(
        args.input,
        language=lang,
        beam_size=5,
        word_timestamps=True,
        vad_filter=True,
        vad_parameters=dict(
            min_silence_duration_ms=300,
            speech_pad_ms=200,
        ),
    )

    detected_lang = info.language
    print(f"Detected language: {detected_lang} (prob={info.language_probability:.2f})")
    print(f"Duration: {info.duration:.1f}s")

    # Collect all segments and words
    segments = []
    all_words = []
    srt_lines = []
    idx = 1

    for seg in segments_gen:
        seg_data = {
            "id": idx,
            "start": round(seg.start, 3),
            "end": round(seg.end, 3),
            "text": seg.text.strip(),
            "words": [],
        }

        # SRT entry
        srt_lines.append(f"{idx}")
        srt_lines.append(f"{format_ts(seg.start)} --> {format_ts(seg.end)}")
        srt_lines.append(seg.text.strip())
        srt_lines.append("")

        if seg.words:
            for w in seg.words:
                word_data = {
                    "word": w.word.strip(),
                    "start": round(w.start, 3),
                    "end": round(w.end, 3),
                    "probability": round(w.probability, 3),
                }
                seg_data["words"].append(word_data)
                all_words.append(word_data)

        segments.append(seg_data)
        idx += 1

        # Progress
        pct = min(100, int(seg.end / info.duration * 100))
        print(f"\r  Progress: {pct}% ({seg.end:.1f}s / {info.duration:.1f}s)", end="", flush=True)

    print(f"\n  Segments: {len(segments)}, Words: {len(all_words)}")

    # Write SRT
    with open(args.output_srt, "w", encoding="utf-8") as f:
        f.write("\n".join(srt_lines))
    print(f"  SRT saved: {args.output_srt}")

    # Write JSON
    result = {
        "language": detected_lang,
        "duration": round(info.duration, 3),
        "segments": segments,
        "words": all_words,
    }
    with open(args.output_json, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)
    print(f"  JSON saved: {args.output_json}")

if __name__ == "__main__":
    main()
