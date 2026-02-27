---
name: hf-multiview-qwen
description: Generate 5-view multi-angle images (front/side/back/top/45-degree) from one or many input photos using the Qwen Image multiple-angles 3D camera Gradio app (Hugging Face or ModelScope mirrors). Use when user asks to create multi-angle turnarounds, camera angle variants, or batch process 10+ images into consistent view sets and return a zip. Prefer API-based Gradio calls (no browser automation) with retries, stable filenames, and quota/queue handling.
---

# Workflow (API-first, batch-ready)

## Inputs / Outputs
- Input: one image or a folder/zip of images (`.jpg/.png/.webp`).
- Output per image: `front.png`, `side.png`, `back.png`, `top.png`, `angle45.png` + `meta.json`.
- Final: zip the `outputs/` folder and send back.

## Steps
1. If user provides a zip, unzip to a clean `inputs/` folder.
2. Create Python venv (PEP668-safe):
   - `python3 -m venv .venv && . .venv/bin/activate`
   - `pip install -U pip && pip install gradio_client pillow tenacity`
3. Run batch generator:
   - `python scripts/generate_multiview.py --input-dir ./inputs --output-dir ./outputs --zip ./multiview_outputs.zip`
4. Send `multiview_outputs.zip` back to the user.

## Default camera presets
- front: azimuth=0, elevation=0, distance=1.0
- side: azimuth=90 (right) or 270 (left), elevation=0, distance=1.0
- back: azimuth=180, elevation=0, distance=1.0
- top: azimuth=0, elevation=60, distance=1.1
- angle45: azimuth=45, elevation=0, distance=1.0

## Failure handling
- If error contains `GPU quota` / `quota exceeded`, stop early and report remaining time.
- For transient errors, rely on script's exponential backoff retries.

## Notes
- Space endpoint: `/infer_camera_edit`.
- Prefer this skill over browser automation for reliability.
