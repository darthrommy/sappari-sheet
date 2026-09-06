<#
.SYNOPSIS
    Builds the Sappari Sheet Windows installer.

.DESCRIPTION
    Wraps ISCC (the Inno Setup compiler) with the three things that must be
    resolved at build time rather than hardcoded in sappari-sheet.iss:

      1. The app version, parsed from pubspec.yaml.
      2. The Visual C++ runtime DLLs, located through vswhere and copied next
         to sappari_sheet.exe so the installed app needs no VC++ redistributable.
         The folder is named after the toolset (Microsoft.VC145.CRT on VS 2026,
         Microsoft.VC143.CRT on the VS 2022 that GitHub runners use), so it has
         to be discovered rather than assumed.
      3. ISCC itself, which lives in a different place depending on how Inno
         Setup was installed.

    Expects `flutter build windows --release` to have been run already.

.PARAMETER SkipRuntimeStaging
    Skip copying the VC++ runtime DLLs. The resulting installer will require
    the end user to have the VC++ redistributable installed.
#>
[CmdletBinding()]
param(
    [switch]$SkipRuntimeStaging
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$installerDir = $PSScriptRoot
$repoRoot = Split-Path -Parent $installerDir
$releaseDir = Join-Path $repoRoot 'build\windows\x64\runner\Release'
$issFile = Join-Path $installerDir 'sappari-sheet.iss'

# --- 1. Version from pubspec.yaml -----------------------------------------
# `version: 26.7.0+1` -> `26.7.0`. Inno wants a plain dotted version; the
# build number after '+' has no meaning on Windows.
$pubspec = Join-Path $repoRoot 'pubspec.yaml'
if (-not (Test-Path $pubspec)) { throw "pubspec.yaml not found at $pubspec" }

$versionLine = Select-String -Path $pubspec -Pattern '^version:\s*(.+)$' | Select-Object -First 1
if (-not $versionLine) { throw "No 'version:' line found in $pubspec" }
$appVersion = ($versionLine.Matches[0].Groups[1].Value.Trim() -split '\+')[0]
if ($appVersion -notmatch '^\d+(\.\d+){1,3}$') {
    throw "Version '$appVersion' from pubspec.yaml is not a plain dotted version Inno Setup accepts."
}
Write-Host "Version:      $appVersion"

# --- 2. The Flutter release build ------------------------------------------
if (-not (Test-Path (Join-Path $releaseDir 'sappari_sheet.exe'))) {
    throw "No release build found at $releaseDir`nRun 'flutter build windows --release' first."
}
Write-Host "Release dir:  $releaseDir"

# --- 3. Stage the Visual C++ runtime ---------------------------------------
# sappari_sheet.exe imports MSVCP140.dll, VCRUNTIME140.dll and VCRUNTIME140_1.dll.
# They are present on any machine with Visual Studio but absent on a clean
# Windows install, so ship them beside the executable (app-local deployment,
# which Windows resolves before the system directory).
$runtimeDlls = @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')

if ($SkipRuntimeStaging) {
    Write-Host "VC++ runtime: skipped (-SkipRuntimeStaging)"
} else {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vswhere)) { throw "vswhere.exe not found at $vswhere — is Visual Studio installed?" }

    $vsPath = & $vswhere -latest -products * -property installationPath
    if (-not $vsPath) { throw "vswhere found no Visual Studio installation." }

    # Prefer the plain x64 redist over the 'onecore' variant, and take the
    # highest toolset version if several are installed.
    $crtDir = Get-ChildItem (Join-Path $vsPath 'VC\Redist\MSVC') -Recurse -Directory -Filter 'Microsoft.VC*.CRT' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\x64\\' -and $_.FullName -notmatch '\\onecore\\' } |
        Sort-Object FullName -Descending |
        Select-Object -First 1

    if (-not $crtDir) { throw "No x64 VC++ redistributable found under $vsPath\VC\Redist\MSVC" }

    # Skip DLLs already staged and identical. Without this the copy fails with a
    # sharing violation whenever the built app is running, which it usually is
    # while iterating.
    $copied = 0
    foreach ($dll in $runtimeDlls) {
        $src = Join-Path $crtDir.FullName $dll
        if (-not (Test-Path $src)) { throw "Expected runtime DLL not found: $src" }
        $dest = Join-Path $releaseDir $dll
        if ((Test-Path $dest) -and
            (Get-Item $dest).Length -eq (Get-Item $src).Length) {
            continue
        }
        Copy-Item $src -Destination $releaseDir -Force
        $copied++
    }
    Write-Host ("VC++ runtime: {0} of {1} DLLs copied from {2} (rest already current)" -f `
            $copied, $runtimeDlls.Count, $crtDir.Name)
}

# --- 4. Locate ISCC ---------------------------------------------------------
# Machine-wide installs (and GitHub's runners) land in Program Files; an
# unelevated `winget install` puts it under %LOCALAPPDATA%\Programs instead.
# Check both, then fall back to the uninstall registry entry and PATH.
$isccCandidates = @(
    (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
    (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe')
)

$uninstallKeys = @(
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
# Most uninstall keys have neither property, and Set-StrictMode makes reading
# a missing one fatal — so check for their presence before touching them.
$registered = Get-ItemProperty $uninstallKeys -ErrorAction SilentlyContinue |
    Where-Object {
        $_.PSObject.Properties['DisplayName'] -and
        $_.PSObject.Properties['InstallLocation'] -and
        $_.DisplayName -like '*Inno Setup*' -and
        $_.InstallLocation
    } |
    ForEach-Object { Join-Path $_.InstallLocation 'ISCC.exe' }

$isccCommand = Get-Command ISCC.exe -ErrorAction SilentlyContinue
$onPath = if ($isccCommand) { $isccCommand.Source } else { $null }

$iscc = @($isccCandidates + $registered + $onPath) |
    Where-Object { $_ -and (Test-Path $_) } |
    Select-Object -First 1

if (-not $iscc) {
    throw "ISCC.exe (Inno Setup 6) not found. Install it with:`n    winget install JRSoftware.InnoSetup"
}
Write-Host "Compiler:     $iscc"

# --- 5. Compile -------------------------------------------------------------
& $iscc "/DAppVersion=$appVersion" "/DSourceDir=$releaseDir" $issFile
if ($LASTEXITCODE -ne 0) { throw "ISCC failed with exit code $LASTEXITCODE" }

$output = Join-Path $installerDir "Output\sappari-sheet-setup-$appVersion.exe"
if (-not (Test-Path $output)) { throw "ISCC reported success but $output does not exist." }

$sizeMb = [math]::Round((Get-Item $output).Length / 1MB, 1)
Write-Host ""
Write-Host "Installer:    $output ($sizeMb MB)"
