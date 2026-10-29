param([switch]$SkipPackage)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
Push-Location $taskRoot
try {
    $taskTools = Join-Path $taskRoot '.work/windows-tools'
    $taskNuget = Join-Path $taskTools 'nuget.exe'
    if (-not (Test-Path -LiteralPath $taskNuget)) {
        New-Item -ItemType Directory -Path $taskTools -Force | Out-Null
        Invoke-WebRequest 'https://dist.nuget.org/win-x86-commandline/v6.14.0/nuget.exe' -OutFile $taskNuget
    }
    $taskSignature = Get-AuthenticodeSignature -LiteralPath $taskNuget
    if ($taskSignature.Status -ne 'Valid' -or
        $taskSignature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
        throw 'NuGet 的 Microsoft 数字签名验证未通过。'
    }
    $taskOldPath = $env:PATH
    try {
        $env:PATH = "$taskTools;$taskOldPath"
        & flutter build windows --release
        if ($LASTEXITCODE -ne 0) { throw 'Windows 构建失败。' }
    } finally { $env:PATH = $taskOldPath }
    if (-not $SkipPackage) {
        $taskVersionLine = Get-Content pubspec.yaml | Where-Object { $_ -match '^version:' }
        $taskVersion = ($taskVersionLine -replace '^version:\s*', '').Split('+')[0].Trim()
        if ($taskVersion -notmatch '^\d+\.\d+\.\d+$') { throw '应用版本无效。' }
        $taskBundle = Join-Path $taskRoot ('.work/windows-package-' + [guid]::NewGuid().ToString('N'))
        $taskApp = Join-Path $taskBundle 'meizizi'
        New-Item -ItemType Directory -Path $taskApp -Force | Out-Null
        Copy-Item -Path 'build/windows/x64/runner/Release/*' -Destination $taskApp -Recurse
        Copy-Item -LiteralPath WINDOWS.md,THIRD_PARTY_NOTICES.md -Destination $taskApp
        New-Item -ItemType Directory -Path releases -Force | Out-Null
        $taskZip = Join-Path $taskRoot "releases/meizizi-windows-$taskVersion.zip"
        Compress-Archive -Path $taskApp -DestinationPath $taskZip -Force
        Write-Host "Windows 压缩包：$taskZip"
    }
} finally { Pop-Location }
