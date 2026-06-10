Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Repository root (one level above tools/)
$repoRoot = Split-Path $PSScriptRoot -Parent
$appName = 'arrows_level_editor'
$binaryName = 'arrows_level_editor'
$pubspecPath = Join-Path $repoRoot 'pubspec.yaml'

if (-not (Test-Path $pubspecPath)) {
  throw "pubspec.yaml not found at $pubspecPath"
}

$pubspec = Get-Content $pubspecPath -Raw
$appVersion = '0.0.0'
if ($pubspec -match 'version:\s*([0-9]+\.[0-9]+\.[0-9]+)') {
  $appVersion = $Matches[1]
}

Write-Host 'Running flutter pub get...'
Push-Location $repoRoot
try {
  & flutter pub get | Out-Default

  Write-Host 'Building Windows release...'
  & flutter build windows --release | Out-Default
} finally {
  Pop-Location
}

$candidateRelPaths = @(
  'build\windows\x64\runner\Release',
  'build\windows\runner\Release',
  'build\windows\Release'
)

$releaseDir = $null
foreach ($relPath in $candidateRelPaths) {
  $full = Join-Path $repoRoot $relPath
  $exePath = Join-Path $full "$binaryName.exe"
  if (Test-Path $exePath) {
    $releaseDir = $full
    break
  }
}

if (-not $releaseDir) {
  throw "Could not find Release output containing $binaryName.exe. Checked: $($candidateRelPaths -join ', ')"
}

$distDir = Join-Path $repoRoot 'dist\windows'
if (-not (Test-Path $distDir)) {
  New-Item -ItemType Directory -Path $distDir | Out-Null
}

$issPath = Join-Path $repoRoot 'tools\installer\inno\installer.iss'
if (-not (Test-Path $issPath)) {
  throw "Installer script not found at $issPath"
}

$expectedOutput = Join-Path $distDir ("$($appName.Replace(' ', '-'))-$appVersion-setup.exe")

$iscc = Get-Command iscc.exe -ErrorAction SilentlyContinue
if (-not $iscc) {
  $fallbackPaths = @(
    'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    'C:\Program Files\Inno Setup 6\ISCC.exe'
  )
  foreach ($p in $fallbackPaths) {
    if (Test-Path $p) {
      $iscc = Get-Item $p
      break
    }
  }
}

if (-not $iscc) {
  throw 'ISCC.exe not found. Install Inno Setup 6 or add ISCC.exe to PATH.'
}

$defines = @(
  "/DAppVersion=$appVersion",
  "/DSourceDir=""$releaseDir""",
  "/DOutputDir=""$distDir"""
)

Write-Host 'Invoking Inno Setup...'
& $iscc @defines $issPath | Out-Default

if ($LASTEXITCODE -ne 0) {
  throw "ISCC failed with exit code $LASTEXITCODE"
}

if (Test-Path $expectedOutput) {
  Write-Host "Installer created: $expectedOutput"
} else {
  Write-Warning "Installer build finished but $expectedOutput was not found."
}
