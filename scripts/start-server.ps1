# SPDX-License-Identifier: AGPL-3.0-only
# Server process is created by LÖVE using CREATE_NO_WINDOW.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
# Bind only to the chosen LAN/VPN adapter, never 0.0.0.0.
$env:PORT = '8080'
if (-not $env:MOO_IO_BIND_IP) { throw 'Endereco do adaptador nao informado.' }
$env:HOST = $env:MOO_IO_BIND_IP
$dataDir = Join-Path $root 'server\data'
New-Item -ItemType Directory -Force $dataDir | Out-Null
$log = Join-Path $dataDir 'mooio-host.log'
try {
  if (-not (Get-Command node.exe -ErrorAction SilentlyContinue)) {
    throw 'Node.js nao esta instalado ou nao consta no PATH.'
  }
  if (-not $env:MOO_IO_ROOM_CODE) {
    throw 'MOO_IO_ROOM_CODE ausente. Inicie a sala pelo cliente Moo IO.'
  }
  $assigned = @(Get-NetIPAddress -AddressFamily IPv4 -IPAddress $env:HOST -ErrorAction SilentlyContinue |
    Where-Object { $_.AddressState -eq 'Preferred' })
  if ($assigned.Count -eq 0) {
    throw "O IP $($env:HOST) nao esta atribuido a um adaptador de rede ativo. Abra sua VPN e use o IP que ela mostra."
  }

  # Prepare images before admitting players. No image is fabricated.
  # Existing local/custom PNGs are preserved; mislabeled WEBP is transcoded.
  if (-not (Test-Path (Join-Path $root 'node_modules\sharp\package.json')) -or
      -not (Test-Path (Join-Path $root 'node_modules\adm-zip\package.json'))) {
    "MOOIO_PHASE_ASSET_DEPENDENCIES" | Out-File $log
    & npm.cmd install --prefix $root --no-audit --no-fund *>> $log
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao instalar conversor de imagens.' }
  }
  "MOOIO_PHASE_ASSETS" | Out-File $log -Append
  & node.exe (Join-Path $root 'tools\sync-reference-art.mjs') *>> $log
  if ($LASTEXITCODE -ne 0) {
    throw 'Falha ao preparar sprites. Consulte ARTES-PENDENTES.txt.'
  }

  if (-not (Test-Path (Join-Path $root 'server\node_modules\ws\package.json'))) {
    "MOOIO_PHASE_INSTALLING" | Out-File $log
    & npm.cmd install --prefix (Join-Path $root 'server') --no-audit --no-fund *>> $log
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao instalar dependencias do servidor.' }
  }
  "MOOIO_PHASE_STARTING" | Out-File $log -Append
  & node.exe (Join-Path $root 'server\src\index.js') *>> $log
  if ($LASTEXITCODE -ne 0) { throw "Servidor encerrou com erro $LASTEXITCODE." }
} catch {
  ("MOOIO_PHASE_ERROR " + $_.ToString()) | Out-File $log -Append
  exit 1
}
