#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

load_profile "${1:-}"
validate_profile
validate_revision
require_runtime_secrets
assert_engine_version
require_model_dir

[[ "${ENGINE}" == "vllm" ]] ||
  die "Profile ${PROFILE_NAME} selects ${ENGINE}, not vllm."
[[ "${SPECULATIVE_DECODING}" == "0" ]] ||
  die "This baseline adapter intentionally refuses speculative decoding."

vllm_bin="$(engine_binary_path)"
[[ -x "${vllm_bin}" ]] || die "vLLM executable not found: ${vllm_bin}"

cmd=(
  "${vllm_bin}" serve "${MODEL_DIR}"
  --served-model-name "${SERVED_MODEL_NAME}"
  --host "${BIND_HOST}"
  --port "${PORT}"
  --api-key "${API_KEY}"
  --max-model-len "${MAX_MODEL_LEN}"
  --gpu-memory-utilization "${GPU_MEMORY_UTILIZATION}"
  --max-num-seqs "${MAX_NUM_SEQS}"
  --max-num-batched-tokens "${MAX_NUM_BATCHED_TOKENS}"
  --seed 0
  --reasoning-parser "${REASONING_PARSER}"
  --tool-call-parser "${TOOL_CALL_PARSER}"
)

if [[ -n "${QUANTIZATION:-}" ]]; then
  cmd+=(--quantization "${QUANTIZATION}")
fi
if [[ -n "${DTYPE:-}" && "${DTYPE}" != "auto" ]]; then
  cmd+=(--dtype "${DTYPE}")
fi
if [[ -n "${KV_CACHE_DTYPE:-}" ]]; then
  cmd+=(--kv-cache-dtype "${KV_CACHE_DTYPE}")
fi
if [[ "${ENABLE_CHUNKED_PREFILL:-0}" == "1" ]]; then
  cmd+=(--enable-chunked-prefill)
fi
if [[ "${ENABLE_PREFIX_CACHING:-0}" == "1" ]]; then
  cmd+=(--enable-prefix-caching)
fi
if [[ "${ENABLE_AUTO_TOOL_CHOICE:-0}" == "1" ]]; then
  cmd+=(--enable-auto-tool-choice)
fi
if [[ -n "${LIMIT_MM_PER_PROMPT:-}" ]]; then
  cmd+=(--limit-mm-per-prompt "${LIMIT_MM_PER_PROMPT}")
fi
if [[ -n "${MM_PROCESSOR_KWARGS:-}" ]]; then
  cmd+=(--mm-processor-kwargs "${MM_PROCESSOR_KWARGS}")
fi
if [[ "${TRUST_REMOTE_CODE}" == "1" ]]; then
  cmd+=(--trust-remote-code)
fi

export HF_HOME="${HF_HOME:-${MODEL_STORE}/.hf-cache}"
export TOKENIZERS_PARALLELISM="${TOKENIZERS_PARALLELISM:-false}"
export PYTORCH_CUDA_ALLOC_CONF="${PYTORCH_CUDA_ALLOC_CONF:-expandable_segments:True}"

info "Launching vLLM ${ENGINE_VERSION}: profile=${PROFILE_NAME}, model=${MODEL_ID}@${MODEL_REVISION}"
info "Endpoint=http://${BIND_HOST}:${PORT}/v1 alias=${SERVED_MODEL_NAME}; API key omitted from logs."
exec "${cmd[@]}"

