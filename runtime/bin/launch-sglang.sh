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

[[ "${ENGINE}" == "sglang" ]] ||
  die "Profile ${PROFILE_NAME} selects ${ENGINE}, not sglang."
[[ "${SPECULATIVE_DECODING}" == "0" ]] ||
  die "This baseline adapter intentionally refuses speculative decoding."

sglang_bin="$(engine_binary_path)"
[[ -x "${sglang_bin}" ]] || die "SGLang executable not found: ${sglang_bin}"

resolve_cuda_home() {
  local nvcc_path=""
  local venv_dir
  local -a bundled_nvcc=()

  if [[ -n "${CUDA_HOME:-}" && -x "${CUDA_HOME}/bin/nvcc" ]]; then
    printf '%s\n' "${CUDA_HOME}"
    return
  fi

  if [[ -n "${CUDA_PATH:-}" && -x "${CUDA_PATH}/bin/nvcc" ]]; then
    printf '%s\n' "${CUDA_PATH}"
    return
  fi

  nvcc_path="$(command -v nvcc 2>/dev/null || true)"
  if [[ -n "${nvcc_path}" && -x "${nvcc_path}" ]]; then
    dirname "$(dirname "${nvcc_path}")"
    return
  fi

  venv_dir="$(dirname "$(dirname "$(engine_python_path)")")"
  shopt -s nullglob
  bundled_nvcc=("${venv_dir}"/lib/python*/site-packages/nvidia/cu*/bin/nvcc)
  shopt -u nullglob

  (( ${#bundled_nvcc[@]} == 1 )) ||
    die "Unable to locate exactly one CUDA compiler. Set CUDA_HOME to a toolkit containing bin/nvcc."
  dirname "$(dirname "${bundled_nvcc[0]}")"
}

CUDA_HOME="$(resolve_cuda_home)"
[[ -x "${CUDA_HOME}/bin/nvcc" ]] ||
  die "CUDA_HOME=${CUDA_HOME} does not contain an executable bin/nvcc."

if [[ ! -e "${CUDA_HOME}/lib64" && -d "${CUDA_HOME}/lib" ]]; then
  ln -s lib "${CUDA_HOME}/lib64"
fi
if [[ ! -e "${CUDA_HOME}/lib64/libcudart.so" && -f "${CUDA_HOME}/lib64/libcudart.so.13" ]]; then
  ln -s libcudart.so.13 "${CUDA_HOME}/lib64/libcudart.so"
fi
find -L "${CUDA_HOME}/lib64" -maxdepth 1 -type f -name 'libcudart.so*' -print -quit |
  grep -q . || die "CUDA_HOME=${CUDA_HOME} has no CUDA runtime library under lib64."
[[ -e "${CUDA_HOME}/lib64/libcudart.so" ]] ||
  die "CUDA_HOME=${CUDA_HOME} has no libcudart.so linker alias under lib64."

export CUDA_HOME
export PATH="${CUDA_HOME}/bin:${PATH}"
export LD_LIBRARY_PATH="${CUDA_HOME}/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

cmd=(
  "${sglang_bin}" serve
  --model-path "${MODEL_DIR}"
  --served-model-name "${SERVED_MODEL_NAME}"
  --host "${BIND_HOST}"
  --port "${PORT}"
  --api-key "${API_KEY}"
  --context-length "${MAX_MODEL_LEN}"
  --mem-fraction-static "${MEM_FRACTION_STATIC}"
  --max-running-requests "${MAX_RUNNING_REQUESTS}"
  --kv-cache-dtype "${KV_CACHE_DTYPE}"
  --attention-backend "${ATTENTION_BACKEND}"
  --chunked-prefill-size "${CHUNKED_PREFILL_SIZE}"
  --mamba-radix-cache-strategy "${MAMBA_RADIX_CACHE_STRATEGY}"
  --mamba-ssm-dtype "${MAMBA_SSM_DTYPE}"
  --max-mamba-cache-size "${MAX_MAMBA_CACHE_SIZE}"
  --cuda-graph-max-bs-decode "${CUDA_GRAPH_MAX_BS_DECODE}"
  --reasoning-parser "${REASONING_PARSER}"
  --tool-call-parser "${TOOL_CALL_PARSER}"
)

if [[ -n "${QUANTIZATION:-}" ]]; then
  cmd+=(--quantization "${QUANTIZATION}")
fi
if [[ -n "${DTYPE:-}" && "${DTYPE}" != "auto" ]]; then
  cmd+=(--dtype "${DTYPE}")
fi
if [[ -n "${MM_FEATURE_TRANSPORT:-}" ]]; then
  cmd+=(--mm-feature-transport "${MM_FEATURE_TRANSPORT}")
fi
if [[ "${ENABLE_METRICS:-0}" == "1" ]]; then
  cmd+=(--enable-metrics)
fi
if [[ "${TRUST_REMOTE_CODE}" == "1" ]]; then
  cmd+=(--trust-remote-code)
fi

export HF_HOME="${HF_HOME:-${MODEL_STORE}/.hf-cache}"
export TOKENIZERS_PARALLELISM="${TOKENIZERS_PARALLELISM:-false}"

info "Launching SGLang ${ENGINE_VERSION}: profile=${PROFILE_NAME}, model=${MODEL_ID}@${MODEL_REVISION}"
info "Endpoint=http://${BIND_HOST}:${PORT}/v1 alias=${SERVED_MODEL_NAME}; API key omitted from logs."
exec "${cmd[@]}"
