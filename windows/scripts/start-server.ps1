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
# Every launch starts with a clean status log. Stale MOOIO_PHASE_ERROR
# records from a previous failed session must never be treated as new.
"MOOIO_PHASE_PREPARING" | Set-Content -Path $log -Encoding UTF8
try {
  # Offline portable release ships the official Node runtime beside the game.
  # Source checkout may use an already installed Node; neither path downloads.
  $bundledNode = Join-Path $root 'runtime\node\node.exe'
  if (Test-Path $bundledNode -PathType Leaf) {
    $nodeExe = $bundledNode
  } else {
    $installed = Get-Command node.exe -ErrorAction SilentlyContinue
    if (-not $installed) {
      throw 'Node ausente. Use o pacote Moo-IO-Windows pronto ou prepare o projeto durante a build.'
    }
    $nodeExe = $installed.Source
  }
  if (-not $env:MOO_IO_ROOM_CODE) {
    throw 'MOO_IO_ROOM_CODE ausente. Inicie a sala pelo cliente Moo IO.'
  }
  $assigned = @(Get-NetIPAddress -AddressFamily IPv4 -IPAddress $env:HOST -ErrorAction SilentlyContinue |
    Where-Object { $_.AddressState -eq 'Preferred' })
  if ($assigned.Count -eq 0) {
    throw "O IP $($env:HOST) nao esta atribuido a um adaptador de rede ativo. Abra sua VPN e use o IP que ela mostra."
  }

  if (-not (Test-Path (Join-Path $root 'server\node_modules\ws\package.json'))) {
    throw 'Dependencias locais ausentes. Distribua o ZIP Windows ja preparado pela build; nao ha download durante o jogo.'
  }
  "MOOIO_PHASE_STARTING" | Out-File $log -Append
  & $nodeExe (Join-Path $root 'server\src\index.js') *>> $log
  if ($LASTEXITCODE -ne 0) { throw "Servidor encerrou com erro $LASTEXITCODE." }
} catch {
  ("MOOIO_PHASE_ERROR " + $_.ToString()) | Out-File $log -Append
  exit 1
}
