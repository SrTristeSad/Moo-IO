# SPDX-License-Identifier: AGPL-3.0-only
# Moo IO - LAN room launcher. Windows PowerShell 5+, Node.js and LOVE 11.5.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$node = Get-Command node.exe -ErrorAction SilentlyContinue
if (-not $node) { throw 'Instale Node.js 20+ e coloque node.exe no PATH.' }
$loveCandidates = @((Join-Path $root 'love.exe'), (Join-Path $env:ProgramFiles 'LOVE\love.exe'))
$pfx86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
if ($pfx86) { $loveCandidates += (Join-Path $pfx86 'LOVE\love.exe') }
$loveCommand = Get-Command love.exe -ErrorAction SilentlyContinue
if ($loveCommand) { $loveCandidates += $loveCommand.Source }
$loveExe = $loveCandidates | Where-Object { $_ -and (Test-Path $_ -PathType Leaf) } | Select-Object -First 1
if (-not $loveExe) { throw 'Instale LOVE 2D 11.5 ou coloque love.exe nesta pasta.' }
Write-Host ''
Write-Host '============ MOO IO ============'
Write-Host '1 - CRIAR SALA LOCAL'
Write-Host '2 - ENTRAR POR CONVITE (LAN)'
Write-Host '==============================='
$choice = Read-Host 'Escolha'
$port = 8080
$env:MOO_IO_PORT = [string]$port
$serverProcess = $null
try {
    if ($choice -eq '1') {
        if (-not (Test-Path (Join-Path $root 'server\node_modules\ws\package.json'))) {
            Write-Host 'Instalando dependencias do servidor...'
            & npm.cmd install --prefix (Join-Path $root 'server') --no-audit --no-fund
            if ($LASTEXITCODE -ne 0) { throw 'Falha no npm install.' }
        }
        try {
            $existing = Invoke-RestMethod "http://127.0.0.1:$port/mooio/status" -TimeoutSec 2
            if ($existing.project -eq 'Moo-IO') { throw "Porta $port ja ocupada por uma sala Moo IO." }
        } catch {
            if ($_.Exception.Message -like 'Porta *ocupada*') { throw }
        }
        $env:MOO_IO_ROOM_CODE = (& $node.Source -e "process.stdout.write(require('node:crypto').randomBytes(8).toString('hex'))").Trim()
        $env:HOST = '0.0.0.0'
        $env:PORT = [string]$port
        $env:MOO_IO_HOST = '127.0.0.1'
        $serverProcess = Start-Process -FilePath $node.Source -ArgumentList @('server/src/index.js') -WorkingDirectory $root -PassThru
        $ready = $false
        for ($i = 0; $i -lt 40; $i++) {
            if ($serverProcess.HasExited) { break }
            try {
                $status = Invoke-RestMethod "http://127.0.0.1:$port/mooio/status" -TimeoutSec 1
                if ($status.project -eq 'Moo-IO') { $ready = $true; break }
            } catch {}
            Start-Sleep -Milliseconds 250
        }
        if (-not $ready) { throw 'Servidor nao iniciou. Confira o Node.js e a porta 8080.' }
        Write-Host ''
        Write-Host 'SALA CRIADA. Convite para amigos na MESMA REDE:'
        $ips = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
           Where-Object { $_.IPAddress -match '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)' } |
           Select-Object -ExpandProperty IPAddress -Unique)
        if ($ips.Count -eq 0) {
            Write-Host "Use SEU-IP-LOCAL:$port/$($env:MOO_IO_ROOM_CODE)"
        } else {
            foreach ($ip in $ips) { Write-Host "$($ip):$port/$($env:MOO_IO_ROOM_CODE)" }
        }
        Write-Host 'Se nao conectarem, confira firewall e isolamento do Wi-Fi.'
        & $loveExe $root
    } elseif ($choice -eq '2') {
        $invite = (Read-Host 'Cole o convite IP:PORTA/CODIGO').Trim()
        if ($invite -notmatch '^([A-Za-z0-9.-]+):([0-9]{1,5})/([A-Za-z0-9-]{8,64})$') {
            throw 'Formato invalido. Exemplo: 192.168.1.10:8080/abcdef1234567890'
        }
        $env:MOO_IO_HOST = $Matches[1]
        $env:MOO_IO_PORT = $Matches[2]
        $env:MOO_IO_ROOM_CODE = $Matches[3]
        if ([int]$env:MOO_IO_PORT -lt 1 -or [int]$env:MOO_IO_PORT -gt 65535) { throw 'Porta invalida.' }
        Write-Host "Conectando ao anfitriao $($env:MOO_IO_HOST):$($env:MOO_IO_PORT)..."
        & $loveExe $root
    } else { throw 'Opcao invalida.' }
} finally {
    if ($serverProcess -and -not $serverProcess.HasExited) {
        Stop-Process -Id $serverProcess.Id -ErrorAction SilentlyContinue
    }
}
