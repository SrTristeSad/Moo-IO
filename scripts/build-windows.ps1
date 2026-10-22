# SPDX-License-Identifier: AGPL-3.0-only
# Builds an OFFLINE-READY Windows directory. No installer or downloads are
# executed on the player's PC. Dependencies must exist on this BUILD machine.
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$LoveDir,
  [Parameter(Mandatory=$true)][string]$NodeExe,
  [string]$OutputDir = ''
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $OutputDir) { $OutputDir = Join-Path $root 'dist\Moo-IO-Windows' }
$OutputDir = [IO.Path]::GetFullPath($OutputDir)
$LoveDir = [IO.Path]::GetFullPath($LoveDir)
$NodeExe = [IO.Path]::GetFullPath($NodeExe)
if (-not (Test-Path (Join-Path $LoveDir 'love.exe') -PathType Leaf)) {
  throw 'LoveDir precisa conter love.exe (LÖVE 11.5 Windows x64).'
}
if (-not (Test-Path $NodeExe -PathType Leaf)) {
  throw 'NodeExe precisa ser node.exe (Windows x64).'
}
if (-not (Test-Path (Join-Path $root 'server\node_modules\ws\package.json') -PathType Leaf)) {
  throw 'Execute npm install --prefix server SOMENTE na maquina de build.'
}
if (-not (Test-Path (Join-Path $root 'assets\custom\img\weapons\hammer_1.png') -PathType Leaf)) {
  throw 'Nao foi encontrado o pacote de artes no checkout.'
}
if ($OutputDir -eq $root -or $OutputDir -eq $LoveDir) {
  throw 'OutputDir nao pode apontar para a origem do projeto nem do LÖVE.'
}
if (Test-Path $OutputDir) { Remove-Item $OutputDir -Recurse -Force }
New-Item -ItemType Directory -Force $OutputDir | Out-Null
# Windows PowerShell Copy-Item can be extremely slow for server/node_modules.
# Robocopy processes the package dependencies in parallel, excluding junctions.
foreach ($folder in @('src','shared','assets','scripts','server')) {
  $from = Join-Path $root $folder
  $to = Join-Path $OutputDir $folder
  New-Item -ItemType Directory -Path $to -Force | Out-Null
  & robocopy.exe $from $to /E /XJ /R:2 /W:1 /MT:16 /NP /NJH /NJS /NFL /NDL | Out-Null
  if ($LASTEXITCODE -ge 8) { throw "Falha ao copiar $folder: codigo $LASTEXITCODE" }
}
foreach ($file in @('main.lua','conf.lua','MOO-IO.vbs','README.md','LICENSE','NOTICE.md')) {
  Copy-Item (Join-Path $root $file) (Join-Path $OutputDir $file) -Force
}
if (Test-Path (Join-Path $root 'licenses')) {
  Copy-Item (Join-Path $root 'licenses') (Join-Path $OutputDir 'licenses') -Recurse -Force
}
# The LÖVE 11.5 Windows ZIP includes its game executable and all required DLLs.
# Preserve the original license/notices shipped with that runtime.
Copy-Item (Join-Path $LoveDir '*') $OutputDir -Recurse -Force
$nodeTarget = Join-Path $OutputDir 'runtime\node'
New-Item -ItemType Directory -Force $nodeTarget | Out-Null
Copy-Item $NodeExe (Join-Path $nodeTarget 'node.exe') -Force
$nodeLicense = Join-Path (Split-Path -Parent $NodeExe) 'LICENSE'
if (-not (Test-Path $nodeLicense -PathType Leaf)) {
  throw 'O runtime Node oficial nao contem LICENSE; build interrompida.'
}
Copy-Item $nodeLicense (Join-Path $nodeTarget 'LICENSE') -Force
# Runtime data, sessions and account files must never be copied from a dev PC.
$data = Join-Path $OutputDir 'server\data'
if (Test-Path $data) { Remove-Item $data -Recurse -Force }
New-Item -ItemType Directory -Force $data | Out-Null
$unwanted = @('server\src\index.js')
foreach ($item in $unwanted) {
  if (-not (Test-Path (Join-Path $OutputDir $item) -PathType Leaf)) {
    throw "Pacote incompleto: $item"
  }
}
& (Join-Path $nodeTarget 'node.exe') --version
if ($LASTEXITCODE -ne 0) { throw 'node.exe embarcado nao inicia.' }
& (Join-Path $nodeTarget 'node.exe') --check (Join-Path $OutputDir 'server\src\index.js')
if ($LASTEXITCODE -ne 0) { throw 'Servidor de distribuicao invalido.' }
$notice = @'
MOO IO - WINDOWS OFFLINE
Este pacote ja inclui LÖVE 11.5, Node.js e dependencias do servidor.
Para jogar: extraia o pacote inteiro e abra MOO-IO.vbs.
Criar uma sala e opcional e so ocorre ao clicar em Criar minha sala.
Na abertura do jogo NAO ha npm install, download ou conversao de PNGs.
Acesso multiplayer requer LAN ou VPN existente (sem downloads pelo jogo).
Os fontes do projeto continuam incluidos para permitir futuras builds.
Node.js e LÖVE sao projetos terceiros; consulte runtime/node/LICENSE
e a documentacao/licencas do LÖVE nesta pasta.
Verifique permissao de redistribuicao de imagens antes de publicar jogos.
'@
[IO.File]::WriteAllText((Join-Path $OutputDir 'LEIA-ME-PRIMEIRO.txt'),$notice)
Write-Host "Pacote Windows offline pronto em: $OutputDir"
