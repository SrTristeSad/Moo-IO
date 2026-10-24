#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# Install as a normal Linux user; no sudo, public ports, firewall edits, or downloads except npm dependencies.
set -euo pipefail
SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd -P)"
ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd -P)"
if [[ "$(uname -s)" != "Linux" ]]; then
  echo "Use este instalador somente no Linux Ubuntu/Debian." >&2
  exit 1
fi
if [[ "$(id -u)" == "0" ]]; then
  echo "Nao execute como root; use um usuario comum (como ubuntu)." >&2
  exit 1
fi
for tool in node npm systemctl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Dependencia ausente: $tool" >&2
    exit 1
  fi
done
if ! systemctl --user show-environment >/dev/null 2>&1; then
  echo "systemd --user indisponivel. Entre por SSH com uma sessao systemd ativa." >&2
  exit 1
fi
cd -- "$ROOT"
node servidor/v2/vps.mjs setup
node servidor/v2/vps.mjs doctor
SERVICE_DIR="$HOME/.config/systemd/user"
mkdir -p -- "$SERVICE_DIR"
SERVICE_FILE="$SERVICE_DIR/mooio-v2.service"
TMP_UNIT="$(mktemp "$SERVICE_DIR/.mooio-v2.XXXXXX")"
trap 'rm -f -- "$TMP_UNIT"' EXIT
node servidor/v2/vps.mjs unit > "$TMP_UNIT"
chmod 600 "$TMP_UNIT"
mv -f -- "$TMP_UNIT" "$SERVICE_FILE"
systemctl --user daemon-reload
systemctl --user enable --now mooio-v2.service
echo
echo "Moo-IO V2 habilitado no systemd do usuario."
echo "Status:   systemctl --user status mooio-v2.service"
echo "Logs:     journalctl --user -u mooio-v2.service -f"
echo "Reiniciar apos editar salas: systemctl --user restart mooio-v2.service"
echo "Para continuar ativo apos sair do SSH, um administrador deve executar:"
echo "  sudo loginctl enable-linger \"$(id -un)\""
echo "Nao abra as portas das salas para a internet; a autenticacao publica ainda nao esta pronta."
