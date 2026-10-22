# SPDX-License-Identifier: AGPL-3.0-only
# Moo IO Windows local server: runtime is installed only at build time.
# This script never downloads packages or runs npm on a player's PC.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$dataDir = Join-Path $root 'server\data'
New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
$log = Join-Path $dataDir 'mooio-host.log'
$stdout = Join-Path $dataDir 'mooio-server-out.log'
$stderr = Join-Path $dataDir 'mooio-server-err.log'
$utf8 = New-Object System.Text.UTF8Encoding($false)
function Write-MooLog([string]$message) {
  [System.IO.File]::AppendAllText($log, ($message + [Environment]::NewLine), $utf8)
}
# The old Windows PowerShell Out-File -Append defaulted to UTF-16 LE,
# corrupting text when appended to Set-Content's UTF-8 status file.
[System.IO.File]::WriteAllText($log, "MOOIO_PHASE_PREPARING" + [Environment]::NewLine, $utf8)
try {
  if (-not $env:MOO_IO_BIND_IP) { throw 'Endereco do adaptador nao informado.' }
  $env:HOST = $env:MOO_IO_BIND_IP
  $env:PORT = '8080'
  if (-not $env:MOO_IO_ROOM_CODE) {
    throw 'Codigo da sala ausente. Crie a sala pelo cliente Moo IO.'
  }

  $bundledNode = Join-Path $root 'runtime\node\node.exe'
  $nodeExe = $null
  if (Test-Path $bundledNode -PathType Leaf) {
    $nodeExe = $bundledNode
  } else {
    $installed = Get-Command node.exe -ErrorAction SilentlyContinue
    if ($installed) { $nodeExe = $installed.Source }
  }
  if (-not $nodeExe) {
    throw 'Node.js nao encontrado. Use o Moo-IO-Windows-Pronto.zip que ja inclui Node, ou instale Node.js para executar o codigo-fonte.'
  }

  $assigned = @(Get-NetIPAddress -AddressFamily IPv4 -IPAddress $env:HOST -ErrorAction SilentlyContinue |
    Where-Object { $_.AddressState -eq 'Preferred' })
  if ($assigned.Count -eq 0) {
    throw "O IP $($env:HOST) nao esta configurado em um adaptador ativo. Confirme o endereco LAN ou da VPN."
  }

  # The prebuilt offline.mjs includes Express, ws and other JS dependencies.
  # Prefer it for BOTH source checkouts and complete packaged releases.
  $offlineEntry = Join-Path $root 'server\src\offline.mjs'
  $devEntry = Join-Path $root 'server\src\index.js'
  if (Test-Path $offlineEntry -PathType Leaf) {
    $entry = $offlineEntry
  } elseif ((Test-Path $devEntry -PathType Leaf) -and
            (Test-Path (Join-Path $root 'server\node_modules\ws\package.json') -PathType Leaf)) {
    $entry = $devEntry
  } else {
    throw 'Servidor local incompleto. Atualize a pasta windows: falta server/src/offline.mjs. O ZIP Windows pronto inclui o servidor e todas as dependencias.'
  }

  Write-MooLog "MOOIO_PHASE_STARTING"
  # Separate logs preserve UTF-8 of the status file in Windows PowerShell 5.1.
  $process = Start-Process -FilePath $nodeExe -ArgumentList ('"' + $entry + '"') -WorkingDirectory $root -NoNewWindow -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
  if ($process.ExitCode -ne 0) {
    $details = ""
    if (Test-Path $stderr -PathType Leaf) {
      $details = ([System.IO.File]::ReadAllText($stderr, $utf8) -split '[\r\n]+' |
        Where-Object { $_.Trim() -ne "" } | Select-Object -Last 2) -join ' | '
    }
    throw ("Servidor Node encerrou com erro " + $process.ExitCode + ". " + $details)
  }
} catch {
  Write-MooLog ("MOOIO_PHASE_ERROR " + $_.Exception.Message)
  exit 1
}
