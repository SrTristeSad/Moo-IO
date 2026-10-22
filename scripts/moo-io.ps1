# SPDX-License-Identifier: AGPL-3.0-only
# Legacy entry point. The only supported way to create/join rooms is through
# the native Moo IO menu. No auto hosting and no npm install at launch.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$launcher = Join-Path $root 'MOO-IO.vbs'
if (-not (Test-Path $launcher -PathType Leaf)) {
  throw 'MOO-IO.vbs nao encontrado nesta pasta.'
}
Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\wscript.exe') -ArgumentList ('"' + $launcher + '"') -WorkingDirectory $root
