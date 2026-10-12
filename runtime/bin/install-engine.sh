#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

load_profile "${1:-}"
validate_profile
need_command python3

venv_dir="${ENGINE_VENV_ROOT}/${ENGINE}-${ENGINE_VERSION}"
python_bin="${venv_dir}/bin/python"
ready_marker="${venv_dir}/.uncensored-ai-engine-ready"

verify_engine_install() {
  "${python_bin}" - <<'PY'
import importlib.metadata as metadata
import huggingface_hub
import sglang
import torch

print(f"sglang={metadata.version('sglang')}")
print(f"torch={torch.__version__}")
print(f"huggingface_hub={huggingface_hub.__version__}")
PY
}

ensure_python_package_version() {
  local package_name="$1"
  local expected_version="$2"
  local actual_version=""

  actual_version="$(
    "${python_bin}" -c \
      'import importlib.metadata as metadata, sys; print(metadata.version(sys.argv[1]))' \
      "${package_name}" 2>/dev/null || true
  )"

  if [[ "${actual_version}" == "${expected_version}" ]]; then
    info "${package_name} ${expected_version} is already installed."
    return
  fi

  info "Installing ${package_name} ${expected_version}."
  "${python_bin}" -m pip install --no-deps --upgrade --force-reinstall \
    "${package_name}==${expected_version}"
}

pin_cuda_toolkit() {
  if [[ -n "${CUDA_RUNTIME_PACKAGE_VERSION:-}" ]]; then
    ensure_python_package_version \
      nvidia-cuda-runtime "${CUDA_RUNTIME_PACKAGE_VERSION}"
  fi

  if [[ -n "${CUDA_COMPILER_PACKAGE_VERSION:-}" ]]; then
    ensure_python_package_version \
      nvidia-cuda-nvcc "${CUDA_COMPILER_PACKAGE_VERSION}"
  fi
}

verify_cuda_compiler_compatibility() {
  "${python_bin}" - <<'PY'
import glob
import os
import re
import subprocess
import sys

import torch

matches = glob.glob(
    f"{sys.prefix}/lib/python*/site-packages/nvidia/cu*/bin/nvcc"
)
if len(matches) != 1:
    raise SystemExit(f"Expected one bundled nvcc compiler, found: {matches}")

output = subprocess.check_output([matches[0], "--version"], text=True)
match = re.search(r"release (\d+\.\d+)", output)
if not match:
    raise SystemExit(f"Could not determine bundled nvcc version from: {output}")

actual = match.group(1)
cuda_home = os.path.dirname(os.path.dirname(matches[0]))
cuda_header = os.path.join(cuda_home, "include", "cuda.h")
with open(cuda_header, encoding="utf-8") as file:
    header = file.read()
header_match = re.search(r"^#define CUDA_VERSION (\d+)$", header, re.MULTILINE)
if not header_match:
    raise SystemExit(f"Could not read CUDA_VERSION from {cuda_header}")

header_version = int(header_match.group(1))
expected = f"{header_version // 1000}.{(header_version % 1000) // 10}"
if actual != expected:
    raise SystemExit(
        f"CUDA compiler {actual} does not match CUDA headers {expected}."
    )

print(f"cuda_compiler={actual}")
print(f"cuda_headers={expected}")
print(f"torch_cuda_build={torch.version.cuda}")
PY
}

mark_engine_ready() {
  "${python_bin}" -m pip freeze > "${venv_dir}/uncensored-ai-freeze.txt"
  printf 'ENGINE=%s\nENGINE_VERSION=%s\nREADY_UTC=%s\n' \
    "${ENGINE}" "${ENGINE_VERSION}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    > "${ready_marker}"
  chmod 600 "${venv_dir}/uncensored-ai-freeze.txt" "${ready_marker}"
}

install -d -m 700 "${ENGINE_VENV_ROOT}"

if [[ -x "${python_bin}" ]]; then
  if actual_version="$(
    "${python_bin}" -c \
      'import importlib.metadata as m, sys; print(m.version(sys.argv[1]))' \
      "${ENGINE}" 2>/dev/null
  )" && [[ "${actual_version}" == "${ENGINE_VERSION}" ]]; then
    pin_cuda_toolkit
    if [[ ! -f "${ready_marker}" ]]; then
      info "Verifying an interrupted or legacy ${ENGINE} installation at ${venv_dir}."
      verify_engine_install || die "Existing environment at ${venv_dir} failed import verification. Preserve its logs, then remove or relocate it manually before retrying."
    fi
    verify_cuda_compiler_compatibility || die "CUDA compiler/header compatibility check failed in ${venv_dir}."
    mark_engine_ready
    info "${ENGINE} ${ENGINE_VERSION} is installed and verified at ${venv_dir}."
    exit 0
  fi
  die "Existing environment at ${venv_dir} is incomplete or has the wrong version. Preserve its logs, then remove or relocate it manually before retrying."
fi

info "Creating isolated environment: ${venv_dir}"
python3 -m venv "${venv_dir}"
"${python_bin}" -m pip install --upgrade pip setuptools wheel

case "${ENGINE}" in
  sglang)
    "${python_bin}" -m pip install "sglang==${ENGINE_VERSION}"
    ;;
  vllm)
    "${python_bin}" -m pip install "vllm==${ENGINE_VERSION}"
    ;;
esac

# Ensure the inspection/download helpers exist in both environments.
"${python_bin}" -m pip install "huggingface_hub>=0.34,<2"
pin_cuda_toolkit

assert_engine_version
verify_engine_install
verify_cuda_compiler_compatibility
mark_engine_ready

"${python_bin}" - <<'PY'
import torch
print(f"torch={torch.__version__}")
print(f"torch_cuda_build={torch.version.cuda}")
print(f"cuda_available={torch.cuda.is_available()}")
if torch.cuda.is_available():
    print(f"gpu={torch.cuda.get_device_name(0)}")
    print(f"compute_capability={torch.cuda.get_device_capability(0)}")
PY

info "Installed ${ENGINE} ${ENGINE_VERSION}. Dependency snapshot: ${venv_dir}/uncensored-ai-freeze.txt"
