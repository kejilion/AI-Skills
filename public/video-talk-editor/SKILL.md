---
name: video-talk-editor
description: >
  Smart video editor for talking-head / oral-broadcast (口播) videos.
  Use when user sends a video file and asks to cut, trim, edit, or
  clean up a talking-head video. Handles: silence removal, subtitle
  burn-in, loudness normalization, jump-cut assembly.
  Default mode: silence-only cutting (simple and reliable).
  Filler-word cutting available via --filler-words flag but disabled by default.
  Supports Chinese and English speech. NOT for VFX, color grading,
  or non-speech video editing.
---

# Video Talk Editor

Smart editing pipeline for talking-head / 口播 videos.
Turns raw footage into tight, watchable clips by removing silence,
filler words, and dead air — automatically.

## Dependencies

On first use, ensure these are installed:

```bash
{baseDir}/scripts/setup.sh
```

This installs: `faster-whisper` (speech recognition), `ffmpeg` (already present),
and Python deps (`pysrt`, `jieba`).

## Core Workflow

### 1. Transcribe

```bash
python3 {baseDir}/scripts/transcribe.sh <input.mp4> [--lang zh|en|auto] [--model large-v3]
```

- Outputs: `<basename>.srt` and `<basename>.json` (word-level timestamps)
- Default model: `large-v3` for Chinese, `medium` for English
- Auto-detects language if `--lang auto`

### 2. Analyze & Plan Cuts

```bash
python3 {baseDir}/scripts/analyze.py <basename>.json <input.mp4> \
  [--silence-thresh -35] \
  [--silence-min 0.6] \
  [--filler-words 嗯,啊,那个,就是,然后,呃,um,uh,like,you_know] \
  [--padding 0.12]
```

- Outputs: `<basename>_cuts.json` — a cut list with keep/remove segments
- Detects: silence gaps, filler words, repeated phrases, scene changes
- Each segment tagged: `keep`, `silence`, `filler`, `repeat`

### 3. Preview Cuts (optional)

Before destructive editing, preview what will be cut:

```bash
python3 {baseDir}/scripts/preview.py <basename>_cuts.json
```

Prints a human-readable timeline showing kept vs removed segments with reasons.
Show this to the user for approval before proceeding.

### 4. Assemble

```bash
python3 {baseDir}/scripts/assemble.py <input.mp4> <basename>_cuts.json \
  [--output edited.mp4] \
  [--crossfade 0.05] \
  [--loudnorm] \
  [--subs <basename>.srt] \
  [--sub-style "FontSize=22,FontName=Noto Sans CJK SC,PrimaryColour=&H00FFFFFF"]
```

- Joins kept segments with optional micro-crossfade (avoids harsh jump cuts)
- `--loudnorm`: EBU R128 loudness normalization
- `--subs`: burn subtitles into video
- Output defaults to `<basename>_edited.mp4`

## Quick One-Shot

For simple "just clean it up" requests:

```bash
{baseDir}/scripts/auto_edit.sh <input.mp4> [--lang zh] [--output cleaned.mp4]
```

Runs the full pipeline (transcribe → analyze → assemble) with sensible defaults.

## Advanced Features

### Split into chapters

```bash
python3 {baseDir}/scripts/split_chapters.py <input.mp4> <basename>.json \
  [--min-chapter 30] [--max-chapter 300]
```

Uses topic shifts and long pauses to split into logical chapters.

### Extract highlights

```bash
python3 {baseDir}/scripts/highlights.py <basename>.json <input.mp4> \
  [--count 3] [--duration 30-60]
```

Picks the most information-dense segments (by speech rate + keyword density) for short-form clips.

### Subtitle-only export

```bash
python3 {baseDir}/scripts/srt_clean.py <basename>.srt \
  [--remove-filler] [--merge-short 1.5]
```

Cleans up SRT: removes filler words, merges short fragments, fixes timing.

## Operational Notes

- All scripts use relative paths from `{baseDir}/scripts/`
- Intermediate files go next to the input video unless `--workdir` is specified
- GPU acceleration: faster-whisper uses CUDA if available, falls back to CPU
- For videos > 2 hours, transcription runs in chunks to limit memory
- Always show the user a cut preview before assembling
- After assembly, report: original duration → edited duration, % removed, segments cut

## Tuning Parameters

See `{baseDir}/references/tuning.md` for detailed parameter guidance:
- Silence detection thresholds by recording environment
- Filler word lists for Chinese/English/Japanese
- Crossfade duration recommendations
- Subtitle styling presets

## Limitations

- Requires `faster-whisper` (Python 3.9+, ~1GB for large-v3 model)
- First run downloads the whisper model (~1.5GB)
- CPU-only transcription is slow (~0.3x realtime for large-v3)
- Not suitable for music videos, multi-speaker interviews (yet), or heavy VFX
