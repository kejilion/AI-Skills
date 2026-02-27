#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""Batch generate multi-view images via HuggingFace Gradio Space.

Space: multimodalart/qwen-image-multiple-angles-3d-camera
Endpoint: /infer_camera_edit

Outputs per input image:
  outputs/<stem>/{front,side,back,top,angle45}.png
  outputs/<stem>/meta.json

Then zip outputs.

Usage:
  python generate_multiview.py --input-dir ./inputs --output-dir ./outputs --zip ./multiview_outputs.zip
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Tuple

from tenacity import retry, retry_if_exception_type, stop_after_attempt, wait_exponential

from gradio_client import Client, handle_file

SPACE = "multimodalart/qwen-image-multiple-angles-3d-camera"
API_NAME = "/infer_camera_edit"


class QuotaExceeded(RuntimeError):
    pass


def is_quota_error(msg: str) -> bool:
    return bool(re.search(r"quota|GPU quota|exceeded your GPU quota", msg, re.I))


@dataclass(frozen=True)
class ViewSpec:
    name: str
    azimuth: float
    elevation: float
    distance: float


DEFAULT_VIEWS = [
    ViewSpec("front", 0, 0, 1.0),
    ViewSpec("side", 90, 0, 1.0),
    ViewSpec("back", 180, 0, 1.0),
    ViewSpec("top", 0, 60, 1.1),
    ViewSpec("angle45", 45, 0, 1.0),
]


def ensure_dir(p: Path) -> None:
    p.mkdir(parents=True, exist_ok=True)


def load_client() -> Client:
    # Note: Client() will resolve the hf.space subdomain and handle queue.
    return Client(SPACE)


@retry(
    retry=retry_if_exception_type(Exception),
    stop=stop_after_attempt(5),
    wait=wait_exponential(multiplier=2, min=5, max=80),
    reraise=True,
)
def infer_one(client: Client, image_path: Path, view: ViewSpec, seed: int = 12345) -> Tuple[Path, int, str]:
    """Run one inference. Returns (output_image_path, seed_used, generated_prompt)."""

    try:
        out_img, out_seed, prompt = client.predict(
            image=handle_file(str(image_path)),
            azimuth=view.azimuth,
            elevation=view.elevation,
            distance=view.distance,
            seed=seed,
            randomize_seed=False,
            guidance_scale=1.0,
            num_inference_steps=4,
            height=1024,
            width=1024,
            api_name=API_NAME,
        )
    except Exception as e:
        msg = str(e)
        if is_quota_error(msg):
            raise QuotaExceeded(msg)
        raise

    out_path = out_img.get("path") if isinstance(out_img, dict) else None
    if not out_path:
        raise RuntimeError(f"No output path returned for view={view.name}")

    return Path(out_path), int(out_seed), str(prompt)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input-dir", required=True)
    ap.add_argument("--output-dir", required=True)
    ap.add_argument("--zip", required=True)
    ap.add_argument("--side", choices=["right", "left"], default="right", help="side view direction")
    ap.add_argument("--distance", type=float, default=1.0, help="base distance for front/side/back")
    ap.add_argument("--top-distance", type=float, default=1.1)
    ap.add_argument("--seed", type=int, default=12345)

    args = ap.parse_args()

    input_dir = Path(args.input_dir)
    output_dir = Path(args.output_dir)
    zip_path = Path(args.zip)

    if not input_dir.exists():
        print(f"Input dir not found: {input_dir}", file=sys.stderr)
        return 2

    ensure_dir(output_dir)

    # Build view specs
    side_az = 90 if args.side == "right" else 270
    views = [
        ViewSpec("front", 0, 0, args.distance),
        ViewSpec("side", side_az, 0, args.distance),
        ViewSpec("back", 180, 0, args.distance),
        ViewSpec("top", 0, 60, args.top_distance),
        ViewSpec("angle45", 45, 0, args.distance),
    ]

    client = load_client()

    images = sorted([p for p in input_dir.iterdir() if p.suffix.lower() in {".jpg", ".jpeg", ".png", ".webp"}])
    if not images:
        print("No images found in input dir", file=sys.stderr)
        return 2

    run_meta: Dict[str, Dict] = {
        "space": SPACE,
        "api": API_NAME,
        "started_at": int(time.time()),
        "views": [view.__dict__ for view in views],
        "results": {},
    }

    for img in images:
        stem = img.stem
        out_sub = output_dir / stem
        ensure_dir(out_sub)
        print(f"\n==> {img.name}")

        per_img_meta = {
            "input": str(img),
            "views": {},
        }

        try:
            for view in views:
                print(f"  - generating {view.name} (az={view.azimuth}, el={view.elevation}, d={view.distance})")
                out_path, out_seed, prompt = infer_one(client, img, view, seed=args.seed)
                dst = out_sub / f"{view.name}.png"
                shutil.copy(out_path, dst)
                per_img_meta["views"][view.name] = {
                    "azimuth": view.azimuth,
                    "elevation": view.elevation,
                    "distance": view.distance,
                    "seed": out_seed,
                    "prompt": prompt,
                    "file": str(dst),
                }
        except QuotaExceeded as e:
            per_img_meta["error"] = "quota_exceeded"
            per_img_meta["message"] = str(e)
            run_meta["results"][stem] = per_img_meta

            # Stop early: quota errors won't fix with retry
            with open(out_sub / "meta.json", "w", encoding="utf-8") as f:
                json.dump(per_img_meta, f, ensure_ascii=False, indent=2)
            print("\n[STOP] GPU quota exceeded. Please wait for quota reset or use PRO/account token.", file=sys.stderr)
            break
        except Exception as e:
            per_img_meta["error"] = "failed"
            per_img_meta["message"] = str(e)
            run_meta["results"][stem] = per_img_meta
            with open(out_sub / "meta.json", "w", encoding="utf-8") as f:
                json.dump(per_img_meta, f, ensure_ascii=False, indent=2)
            print(f"[WARN] failed on {img.name}: {e}", file=sys.stderr)
            continue

        run_meta["results"][stem] = per_img_meta
        with open(out_sub / "meta.json", "w", encoding="utf-8") as f:
            json.dump(per_img_meta, f, ensure_ascii=False, indent=2)

    run_meta["finished_at"] = int(time.time())
    with open(output_dir / "run_meta.json", "w", encoding="utf-8") as f:
        json.dump(run_meta, f, ensure_ascii=False, indent=2)

    # Zip
    if zip_path.exists():
        zip_path.unlink()
    base_name = str(zip_path.with_suffix(""))
    archive = shutil.make_archive(base_name, "zip", root_dir=output_dir)
    print(f"\nZipped: {archive}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
