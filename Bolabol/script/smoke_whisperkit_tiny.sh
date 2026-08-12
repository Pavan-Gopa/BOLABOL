#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUDIO_PATH="${AUDIO_PATH:-"$ROOT_DIR/../jfk.wav"}"
MODEL_CACHE="${MODEL_CACHE:-/tmp/native-bolabol-whisperkit-smoke-models}"
TOKENIZER_CACHE="${TOKENIZER_CACHE:-/tmp/native-bolabol-whisperkit-smoke-tokenizers}"
REPORT_DIR="${REPORT_DIR:-/tmp/native-bolabol-whisperkit-report}"
MODEL_PATH="$MODEL_CACHE/models/argmaxinc/whisperkit-coreml/openai_whisper-tiny"

cd "$ROOT_DIR"

if [[ ! -f "$AUDIO_PATH" ]]; then
  echo "Missing smoke audio fixture: $AUDIO_PATH" >&2
  exit 2
fi

mkdir -p "$MODEL_CACHE" "$TOKENIZER_CACHE" "$REPORT_DIR"

set +e
OUTPUT="$(
  swift run argmax-cli transcribe \
    --audio-path "$AUDIO_PATH" \
    --model-path "$MODEL_PATH" \
    --model tiny \
    --download-model-path "$MODEL_CACHE" \
    --download-tokenizer-path "$TOKENIZER_CACHE" \
    --language en \
    --without-timestamps \
    --skip-special-tokens \
    --audio-encoder-compute-units cpuAndNeuralEngine \
    --text-decoder-compute-units cpuAndNeuralEngine \
    --report \
    --report-path "$REPORT_DIR" \
    --verbose 2>&1
)"
STATUS=$?
set -e

printf '%s\n' "$OUTPUT"

if [[ "$STATUS" -ne 0 ]]; then
  exit "$STATUS"
fi

if ! grep -qi "ask not what your country" <<<"$OUTPUT"; then
  echo "WhisperKit Tiny smoke test did not produce the expected transcript." >&2
  exit 1
fi

echo "WhisperKit Tiny smoke test passed."
