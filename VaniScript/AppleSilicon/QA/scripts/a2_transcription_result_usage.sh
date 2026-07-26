#!/usr/bin/env bash
# QA/scripts/a2_transcription_result_usage.sh — A2 (§8.1): CloudAudioTranscriptionEngine
# returns token usage. Assert CloudAudioTranscriptionResult.usage: TokenUsage? (default
# nil), both Gemini/OpenAI transcribe paths parse usage via UsageRecorder and thread it
# into the result. (Scope note: NativeProcessingPipeline -> settings.usage wiring is
# DEFERRED to A5/A6 — we only assert the engine RETURNS usage here.)
set -uo pipefail
AS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$AS_DIR"

FILE="Sources/VaniScript/Services/CloudAudioTranscriptionEngine.swift"
[[ -f "$FILE" ]] || { echo "FAIL: $FILE missing"; exit 1; }

grep -Fq "struct CloudAudioTranscriptionResult: Sendable" "$FILE" \
  || { echo "FAIL: CloudAudioTranscriptionResult missing"; exit 1; }
grep -Fq "var usage: TokenUsage? = nil" "$FILE" \
  || { echo "FAIL: result must carry 'usage: TokenUsage? = nil'"; exit 1; }
# Both provider paths return (text, usage) and parse via the Core recorder.
grep -Fq ") async throws -> (text: String, usage: TokenUsage?)" "$FILE" \
  || { echo "FAIL: transcribe helpers must return (text, usage: TokenUsage?)"; exit 1; }
grep -Fq "let usage = UsageRecorder.parseGeminiUsage(from: data)" "$FILE" \
  || { echo "FAIL: Gemini transcription must parse usage via UsageRecorder.parseGeminiUsage"; exit 1; }
grep -Fq "let usage = UsageRecorder.parseOpenAIUsage(from: data)" "$FILE" \
  || { echo "FAIL: OpenAI transcription must parse usage via UsageRecorder.parseOpenAIUsage"; exit 1; }
# Usage is threaded into the returned result.
grep -Fq "usage: usage" "$FILE" \
  || { echo "FAIL: transcription result must be constructed with usage:"; exit 1; }

echo "PASS: CloudAudioTranscriptionEngine returns TokenUsage from both Gemini and OpenAI paths."
