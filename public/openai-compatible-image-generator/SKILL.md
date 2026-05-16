---
name: openai-compatible-image-generator
description: Generate images through OpenAI-compatible /v1/images/generations APIs such as gpt-image-2, custom proxy endpoints, or self-hosted image gateways. Use when the user asks to test an image-generation endpoint, adapt a script to a base URL/API key/model, generate one or many images from prompts, or package a reusable OpenAI-compatible image generation workflow.
---

# OpenAI-Compatible Image Generator

Use this skill for image generation through providers that expose an OpenAI-style endpoint:

```text
POST {base_url}/images/generations
Authorization: Bearer <api_key>
Content-Type: application/json
```

## Default Workflow

1. Prefer the bundled script unless the user explicitly wants a different implementation:
   ```bash
   python3 {baseDir}/scripts/generate_image.py "prompt" \
     --base-url "$IMAGE_API_BASE_URL" \
     --api-key "$IMAGE_API_KEY" \
     --model gpt-image-2 \
     --size 1024x1024 \
     --out ./generated.png
   ```
2. Keep API keys out of source files, chat replies, and git commits. Use environment variables or secret/config files already present on the machine.
3. Verify success with both process exit code and output file existence:
   ```bash
   test -s ./generated.png && file ./generated.png
   ```
4. If sending the result in chat, attach the generated image rather than pasting base64.

## Environment Variables

The script checks these names in order:

- Base URL: `IMAGE_API_BASE_URL`, `GPT_IMAGE2_BASE_URL`, `OPENAI_BASE_URL`
- API key: `IMAGE_API_KEY`, `GPT_IMAGE2_API_KEY`, `OPENAI_API_KEY`
- Model: `IMAGE_MODEL`, `GPT_IMAGE2_MODEL` (default: `gpt-image-2`)
- Size: `IMAGE_SIZE` (default: `1024x1024`)

## Script Features

`generate_image.py` supports:

- `b64_json` responses: decodes and writes PNG bytes to disk.
- `url` responses: prints URL, or downloads it when `--out` is a file path for `n=1`.
- Multiple images: set `--n > 1` and pass `--out` as a directory.
- Provider-specific fields: pass `--extra-json '{"key":"value"}'` to merge additional request payload fields.
- Nonstandard auth: pass `--auth-prefix ''` for raw key auth, or another prefix if the gateway requires it.

## Common Commands

Single image:

```bash
IMAGE_API_BASE_URL="https://example.com/v1" \
IMAGE_API_KEY="sk-..." \
python3 {baseDir}/scripts/generate_image.py "一只戴墨镜的小狮子，简洁科技风图标" \
  --model gpt-image-2 \
  --out /root/.openclaw/workspace/outputs/lion.png
```

Batch variants:

```bash
mkdir -p /root/.openclaw/workspace/outputs/image_batch
python3 {baseDir}/scripts/generate_image.py "cyberpunk city poster" \
  --base-url "$IMAGE_API_BASE_URL" \
  --api-key "$IMAGE_API_KEY" \
  --model gpt-image-2 \
  --n 4 \
  --out /root/.openclaw/workspace/outputs/image_batch
```

## Troubleshooting

- `Missing API key`: pass `--api-key` or set one of the supported key environment variables.
- `HTTP 401/403`: check key, auth prefix, and whether the provider expects `Bearer`.
- `HTTP 404`: ensure the base URL ends at `/v1`; the script appends `/images/generations`.
- Empty `data`: print the provider response and inspect whether it uses a nonstandard schema.
- Long waits/timeouts: increase `--timeout`, reduce `--n`, or test with a shorter prompt.
