# Local artwork preparation for every Moo-IO launch, including join-only clients.
# Invoked invisibly by MOO-IO.vbs. PNGs are verified; WebPs mislabeled as
# .png are transcoded without redrawing the user or third-party art.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$dataDir = Join-Path $root 'server\data'
New-Item -ItemType Directory -Force $dataDir | Out-Null
$log = Join-Path $dataDir 'mooio-assets.log'
try {
  if (-not (Get-Command node.exe -ErrorAction SilentlyContinue)) {
    throw 'Node.js 20+ nao encontrado. Instale Node.js antes de jogar.'
  }
  if (-not (Get-Command npm.cmd -ErrorAction SilentlyContinue)) {
    throw 'npm nao encontrado. Reinstale o Node.js.'
  }
  if (-not (Test-Path (Join-Path $root 'node_modules\sharp\package.json')) -or
      -not (Test-Path (Join-Path $root 'node_modules\adm-zip\package.json'))) {
    "MOOIO_PHASE_ASSET_DEPENDENCIES" | Out-File $log
    & npm.cmd install --prefix $root --no-audit --no-fund *>> $log
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao instalar conversor de imagens.' }
  }
  "MOOIO_PHASE_ASSETS" | Out-File $log -Append
  & node.exe (Join-Path $root 'tools\sync-reference-art.mjs') *>> $log
  if ($LASTEXITCODE -ne 0) {
    throw 'Falha ao preparar PNGs. Consulte ARTES-PENDENTES.txt.'
  }
  "MOOIO_PHASE_ASSETS_READY" | Out-File $log -Append
} catch {
  ("MOOIO_PHASE_ERROR " + $_.ToString()) | Out-File $log -Append
  exit 1
}
