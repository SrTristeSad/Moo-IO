# SPDX-License-Identifier: AGPL-3.0-only
# Server process is created by LÖVE using CREATE_NO_WINDOW.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$env:HOST = '0.0.0.0'
$env:PORT = '8080'
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
  if (-not (Test-Path (Join-Path $root 'server\node_modules\ws\package.json'))) {
    "Instalando dependencias do servidor..." | Out-File $log
    & npm.cmd install --prefix (Join-Path $root 'server') --no-audit --no-fund *>> $log
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao instalar dependencias do servidor.' }
  }
  "Iniciando Moo IO Node.js..." | Out-File $log -Append
  & node.exe (Join-Path $root 'server\src\index.js') *>> $log
  if ($LASTEXITCODE -ne 0) { throw "Servidor encerrou com erro $LASTEXITCODE." }
} catch {
  $_.ToString() | Out-File $log -Append
  exit 1
}
