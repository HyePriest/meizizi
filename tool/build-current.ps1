param([string]$Flutter = 'E:\Android\flutter\bin\flutter.bat')
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$taskPreviousJava = $env:JAVA_HOME
Push-Location -LiteralPath $taskRoot
try {
    $env:JAVA_HOME = 'E:\Android\Android Studio\jbr'
    & $Flutter pub get --offline
    if ($LASTEXITCODE -ne 0) { throw 'Offline dependencies unavailable.' }
    # Build the current app with its original identity and signing.
    & $Flutter build apk --release --target-platform android-arm64 --no-pub `
        --obfuscate --split-debug-info=.maintenance/symbols `
        --extra-gen-snapshot-options=--strip
    if ($LASTEXITCODE -ne 0) { throw 'Build failed.' }
    $taskName = 'meizizi-current-arm64.apk'
    $taskOutput = Join-Path $taskRoot "build/app/outputs/flutter-apk/$taskName"
    Copy-Item -LiteralPath (Join-Path $taskRoot 'build/app/outputs/flutter-apk/app-release.apk') -Destination $taskOutput -Force
    Write-Host $taskOutput
} finally {
    $env:JAVA_HOME = $taskPreviousJava
    Pop-Location
}
