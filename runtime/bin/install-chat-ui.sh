#!/usr/bin/env bash
# Install the reviewed Docker prerequisites for the optional server-hosted chat UI.

set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  info "Docker Compose is already available for the server-hosted chat UI."
  exit 0
fi

if ! command -v apt-get >/dev/null 2>&1; then
  die "Server-hosted Open WebUI setup currently supports Ubuntu/Debian with apt-get."
fi

elevated=()
if (( EUID != 0 )); then
  need_command sudo
  elevated=(sudo)
fi

info "Installing Docker Engine and Docker Compose from the Ubuntu/Debian package repository."
"${elevated[@]}" apt-get update
"${elevated[@]}" env DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io docker-compose-v2

if command -v systemctl >/dev/null 2>&1; then
  "${elevated[@]}" systemctl enable --now docker
fi

need_command docker
if ! docker compose version >/dev/null 2>&1 && ! "${elevated[@]}" docker compose version >/dev/null 2>&1; then
  die "Docker Compose was not installed successfully."
fi
info "Docker Compose setup completed."
