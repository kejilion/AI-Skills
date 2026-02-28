#!/usr/bin/env bash
# Transcribe video to SRT + JSON (word-level timestamps)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
  echo "Usage: $0 <input_video> [--lang zh|en|auto] [--model large-v3|medium|small] [--workdir DIR]"
  exit 1
}

INPUT=""
LANG="auto"
MODEL=""
WORKDIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lang) LANG="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --workdir) WORKDIR="$2"; shift 2 ;;
    --help|-h) usage ;;
    *) INPUT="$1"; shift ;;
  esac
done

[[ -z "$INPUT" ]] && usage
[[ ! -f "$INPUT" ]] && echo "ERROR: File not found: $INPUT" && exit 1

BASENAME="$(basename "${INPUT%.*}")"
DIR="${WORKDIR:-$(dirname "$INPUT")}"

# Auto-select model based on language
if [[ -z "$MODEL" ]]; then
  if [[ "$LANG" == "zh" ]]; then
    MODEL="large-v3"
  else
    MODEL="medium"
  fi
fi

echo "Transcribing: $INPUT"
echo "Language: $LANG | Model: $MODEL"
echo "Output: $DIR/${BASENAME}.srt + $DIR/${BASENAME}.json"

python3 "${SCRIPT_DIR}/transcribe_worker.py" \
  "$INPUT" \
  --lang "$LANG" \
  --model "$MODEL" \
  --output-srt "$DIR/${BASENAME}.srt" \
  --output-json "$DIR/${BASENAME}.json"

echo ""
echo "Done. Files:"
echo "  SRT: $DIR/${BASENAME}.srt"
echo "  JSON: $DIR/${BASENAME}.json"
