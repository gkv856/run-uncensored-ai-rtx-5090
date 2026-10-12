#!/usr/bin/env bash
# Disable the boot guardian without deleting model files, UI data, or credentials.

set -Eeuo pipefail
umask 077

need_command systemctl

elevated=()
if (( EUID != 0 )); then
  need_command sudo
  elevated=(sudo)
fi

"${elevated[@]}" systemctl disable --now uncensored-ai-stack.service || true
"${elevated[@]}" rm -f /etc/systemd/system/uncensored-ai-stack.service
"${elevated[@]}" systemctl daemon-reload
printf '[info] Automatic startup was disabled. Existing model files, UI data, and credentials were retained.\n'
