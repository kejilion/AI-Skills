#!/usr/bin/env bash
# Auto-edit: one-shot pipeline for quick cleanup
# Usage: auto_edit.sh <input.mp4> [--lang zh] [--output cleaned.mp4]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

INPUT=""
LANG="auto"
OUTPUT=""
LOUDNORM="--loudnorm"
SUBS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lang) LANG="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --no-loudnorm) LOUDNORM=""; shift ;;
    --subs) SUBS="yes"; shift ;;
    --help|-h)
      echo "Usage: $0 <input.mp4> [--lang zh|en|auto] [--output out.mp4] [--subs] [--no-loudnorm]"
      exit 0 ;;
    *) INPUT="$1"; shift ;;
  esac
done

if [[ -z "$INPUT" ]]; then
  echo "ERROR: No input file specified"
  exit 1
fi

BASENAME="$(basename "${INPUT%.*}")"
DIR="$(dirname "$INPUT")"
[[ -z "$OUTPUT" ]] && OUTPUT="${DIR}/${BASENAME}_edited.mp4"

echo "========================================"
echo "  Video Talk Editor - Auto Edit"
echo "========================================"
echo "  Input:  $INPUT"
echo "  Output: $OUTPUT"
echo "  Lang:   $LANG"
echo "========================================"
echo ""

# Step 1: Transcribe
echo "[1/4] Transcribing..."
bash "${SCRIPT_DIR}/transcribe.sh" "$INPUT" --lang "$LANG"
echo ""

# Step 2: Analyze
echo "[2/4] Analyzing for cuts..."
python3 "${SCRIPT_DIR}/analyze.py" "${DIR}/${BASENAME}.json" "$INPUT"
echo ""

# Step 3: Preview
echo "[3/4] Cut preview:"
python3 "${SCRIPT_DIR}/preview.py" "${DIR}/${BASENAME}_cuts.json"
echo ""

# Step 4: Assemble
echo "[4/4] Assembling..."
ASSEMBLE_ARGS=("$INPUT" "${DIR}/${BASENAME}_cuts.json" --output "$OUTPUT" --crossfade 0.05)
[[ -n "$LOUDNORM" ]] && ASSEMBLE_ARGS+=($LOUDNORM)
[[ -n "$SUBS" ]] && ASSEMBLE_ARGS+=(--subs "${DIR}/${BASENAME}.srt")

python3 "${SCRIPT_DIR}/assemble.py" "${ASSEMBLE_ARGS[@]}"

echo ""
echo "========================================"
echo "  Done!"
echo "  Output: $OUTPUT"
echo "========================================"
