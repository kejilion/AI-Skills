#!/usr/bin/env python3
"""Generate images through an OpenAI-compatible /v1/images/generations endpoint.

Examples:
  export IMAGE_API_KEY='sk-...'
  python3 generate_image.py '一只小猫' --base-url https://api.example.com/v1 --model gpt-image-2 --out out.png

  python3 generate_image.py 'logo icon' --n 4 --out ./outputs
"""
from __future__ import annotations

import argparse
import base64
import json
import mimetypes
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any


def env_first(*names: str, default: str = "") -> str:
    for name in names:
        value = os.environ.get(name)
        if value:
            return value
    return default


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate images via OpenAI-compatible image API")
    parser.add_argument("prompt", help="Image prompt")
    parser.add_argument("--base-url", default=env_first("IMAGE_API_BASE_URL", "GPT_IMAGE2_BASE_URL", "OPENAI_BASE_URL", default=""), help="Base URL, e.g. https://api.example.com/v1")
    parser.add_argument("--api-key", default=env_first("IMAGE_API_KEY", "GPT_IMAGE2_API_KEY", "OPENAI_API_KEY", default=""), help="API key; prefer environment variables")
    parser.add_argument("--model", default=env_first("IMAGE_MODEL", "GPT_IMAGE2_MODEL", default="gpt-image-2"), help="Image model name")
    parser.add_argument("--size", default=env_first("IMAGE_SIZE", default="1024x1024"), help="Image size, e.g. 1024x1024")
    parser.add_argument("--n", type=int, default=int(env_first("IMAGE_N", default="1")), help="Number of images")
    parser.add_argument("--quality", default=env_first("IMAGE_QUALITY", default=""), help="Optional quality parameter if supported by provider")
    parser.add_argument("--style", default=env_first("IMAGE_STYLE", default=""), help="Optional style parameter if supported by provider")
    parser.add_argument("--response-format", choices=["b64_json", "url", "auto"], default=env_first("IMAGE_RESPONSE_FORMAT", default="auto"), help="Request b64_json or url when provider supports it")
    parser.add_argument("--out", default=env_first("IMAGE_OUT", default="./generated.png"), help="Output file for n=1, or output directory for n>1")
    parser.add_argument("--timeout", type=int, default=int(env_first("IMAGE_TIMEOUT", default="180")), help="HTTP timeout seconds")
    parser.add_argument("--extra-json", default="", help="Extra JSON object merged into request payload")
    parser.add_argument("--auth-prefix", default=env_first("IMAGE_AUTH_PREFIX", default="Bearer"), help="Authorization prefix; default Bearer")
    return parser.parse_args()


def fail(message: str, code: int = 1) -> int:
    print(message, file=sys.stderr)
    return code


def output_path(base: Path, idx: int, item: dict[str, Any], n: int) -> Path:
    if n == 1:
        return base
    base.mkdir(parents=True, exist_ok=True)
    ext = ".png"
    if item.get("url"):
        guessed = mimetypes.guess_extension((item.get("mime_type") or "").split(";")[0])
        if guessed:
            ext = guessed
    return base / f"image-{int(time.time())}-{idx}{ext}"


def download_url(url: str, path: Path, timeout: int) -> None:
    req = urllib.request.Request(url, headers={"User-Agent": "openai-compatible-image-generator/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(resp.read())


def main() -> int:
    args = parse_args()
    if not args.base_url:
        return fail("Missing base URL: pass --base-url or set IMAGE_API_BASE_URL/GPT_IMAGE2_BASE_URL/OPENAI_BASE_URL", 2)
    if not args.api_key:
        return fail("Missing API key: pass --api-key or set IMAGE_API_KEY/GPT_IMAGE2_API_KEY/OPENAI_API_KEY", 2)
    if args.n < 1:
        return fail("--n must be >= 1", 2)

    payload: dict[str, Any] = {
        "model": args.model,
        "prompt": args.prompt,
        "size": args.size,
        "n": args.n,
    }
    if args.quality:
        payload["quality"] = args.quality
    if args.style:
        payload["style"] = args.style
    if args.response_format != "auto":
        payload["response_format"] = args.response_format
    if args.extra_json:
        try:
            extra = json.loads(args.extra_json)
        except json.JSONDecodeError as exc:
            return fail(f"Invalid --extra-json: {exc}", 2)
        if not isinstance(extra, dict):
            return fail("--extra-json must decode to a JSON object", 2)
        payload.update(extra)

    endpoint = args.base_url.rstrip("/") + "/images/generations"
    auth_value = f"{args.auth_prefix} {args.api_key}" if args.auth_prefix else args.api_key
    req = urllib.request.Request(
        endpoint,
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers={"Authorization": auth_value, "Content-Type": "application/json"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=args.timeout) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="ignore")
        return fail(f"HTTP {exc.code}: {body}")
    except Exception as exc:  # noqa: BLE001 - CLI should report provider/network failures plainly
        return fail(f"Request failed: {exc!r}")

    images = data.get("data") or []
    if not images:
        return fail("No images in response:\n" + json.dumps(data, ensure_ascii=False, indent=2))

    out = Path(args.out)
    outputs: list[str] = []
    for idx, item in enumerate(images, start=1):
        if not isinstance(item, dict):
            print(json.dumps(item, ensure_ascii=False), file=sys.stderr)
            continue
        path = output_path(out, idx, item, args.n)
        if item.get("b64_json"):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(base64.b64decode(item["b64_json"]))
            outputs.append(str(path))
        elif item.get("url"):
            # Print remote URLs by default; if output has a file suffix, download single-url output.
            if args.n == 1 and out.suffix:
                download_url(item["url"], path, args.timeout)
                outputs.append(str(path))
            else:
                outputs.append(item["url"])
        else:
            print(json.dumps(item, ensure_ascii=False, indent=2), file=sys.stderr)

    for result in outputs:
        print(result)
    return 0 if outputs else 1


if __name__ == "__main__":
    raise SystemExit(main())
