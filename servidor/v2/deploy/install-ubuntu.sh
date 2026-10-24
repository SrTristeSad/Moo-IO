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
# Install a separate user service for the admin UI. Only start it once its
# dedicated password exists; never generate a default password.
PANEL_UNIT="$SERVICE_DIR/mooio-v2-panel.service"
PANEL_TEMP="$(mktemp "$SERVICE_DIR/.mooio-v2-panel.XXXXXX")"
trap 'rm -f -- "$TMP_UNIT" "$PANEL_TEMP"' EXIT
node servidor/v2/vps.mjs panel-unit > "$PANEL_TEMP"
chmod 600 "$PANEL_TEMP"
mv -f -- "$PANEL_TEMP" "$PANEL_UNIT"
systemctl --user daemon-reload
if node servidor/v2/panel.mjs check >/dev/null 2>&1; then
  systemctl --user enable --now mooio-v2-panel.service
  echo "Painel local iniciado em http://127.0.0.1:8787 (somente SSH/loopback)."
else
  echo "Painel instalado mas NAO iniciado: falta definir a senha administrativa."
  echo "Depois de configurar com 'node servidor/v2/panel.mjs password', execute:"
  echo "  systemctl --user enable --now mooio-v2-panel.service"
fi
# The browser identity service is opt-in until a real HTTPS origin is set.
# Never auto-publish a login domain or create credentials as side effects.
IDENTITY_UNIT="$SERVICE_DIR/mooio-v2-identity.service"
IDENTITY_TEMP="$(mktemp "$SERVICE_DIR/.mooio-v2-identity.XXXXXX")"
trap 'rm -f -- "$TMP_UNIT" "$PANEL_TEMP" "$IDENTITY_TEMP"' EXIT
node servidor/v2/vps.mjs identity-unit > "$IDENTITY_TEMP"
chmod 600 "$IDENTITY_TEMP"
mv -f -- "$IDENTITY_TEMP" "$IDENTITY_UNIT"
systemctl --user daemon-reload
if node servidor/v2/identity.mjs check >/dev/null 2>&1; then
  systemctl --user enable --now mooio-v2-identity.service
  echo "Identidade V2 ativa somente em 127.0.0.1:8788; use HTTPS Caddy."
else
  echo "Identidade V2 instalada e desativada; falta configurar --origin HTTPS."
  echo "  node servidor/v2/identity.mjs configure --origin https://auth.SEUDOMINIO"
  echo "  systemctl --user enable --now mooio-v2-identity.service"
fi
echo
echo "Moo-IO V2 habilitado no systemd do usuario."
echo "Status:   systemctl --user status mooio-v2.service"
echo "Logs:     journalctl --user -u mooio-v2.service -f"
echo "Salas:    node servidor/v2/manager.mjs status"
echo "Painel:   systemctl --user status mooio-v2-panel.service"
echo "Logs:     journalctl --user -u mooio-v2-panel.service -f"
echo "Identidade: systemctl --user status mooio-v2-identity.service"
echo "Nova sala nao exige reiniciar todo o controlador."
echo "Para continuar ativo apos sair do SSH, um administrador deve executar:"
echo "  sudo loginctl enable-linger \"$(id -un)\""
echo "Nao abra 8787, 8788 nem as portas internas das salas na Internet."
