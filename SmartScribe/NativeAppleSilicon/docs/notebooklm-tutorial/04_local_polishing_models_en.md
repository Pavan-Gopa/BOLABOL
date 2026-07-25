# 03. Polishing: Local MLX Models

## `04_local_polishing_models_settings.png`

This tab manages text polishing, not speech recognition. It shows local MLX models such as Qwen 3.5 and NVIDIA Nemotron-3 Nano. The top card contains `Scan for Local Models`.

## What Polishing Means

Polishing does not listen to audio. It takes text and applies a prompt: cleanup, stronger rewrite, or Markdown formatting.

## Choosing a Model

- `0.8B` is a light testing model: fast, lower quality.
- `2B` is fast for short polishing.
- `4B` is the recommended balance.
- `9B` gives higher quality but is slower and heavier.
- Nemotron-3 Nano 4B is a compact alternative.

## Scan for Local Models

The scan checks:

- shared `~/AI_LOCAL_MODELS/mlx`;
- Hugging Face cache `~/.cache/huggingface/hub`;
- `~/Documents`;
- `~/Downloads`.

Compatible local MLX text-generation models are added to the list. Removing a custom model removes it only from SmartScribe's list; it does not delete model files from disk.

## Important Warning

Reasoning/thinking models can leak thinking text into the output and are slower. For polishing, a non-reasoning instruct model is usually better.

