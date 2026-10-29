param(
    [string]$Compiler,
    [string]$RuntimeDirectory
)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
$taskRelease = Join-Path $taskRoot 'build/windows/x64/runner/Release'
$taskExecutable = Join-Path $taskRelease 'meizizi.exe'
if (-not (Test-Path -LiteralPath $taskExecutable)) {
    throw '请先构建 Windows Release 版本。'
}
$taskVersion = (Get-Item -LiteralPath $taskExecutable).VersionInfo.ProductVersion.Split('+')[0]
if ($taskVersion -notmatch '^\d+\.\d+\.\d+$') { throw '无法读取 EXE 的版本号。' }

if (-not $Compiler) {
    $taskCandidates = @(
        (Join-Path $taskRoot '.work/inno-setup/ISCC.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs/Inno Setup 7/ISCC.exe'),
        (Join-Path ${env:ProgramFiles} 'Inno Setup 7/ISCC.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6/ISCC.exe')
    )
    $Compiler = $taskCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (-not $Compiler -or -not (Test-Path -LiteralPath $Compiler)) {
    throw '请安装 Inno Setup 7，或使用 -Compiler 指定 ISCC.exe。'
}

if (-not $RuntimeDirectory) {
    $taskVsWhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    if (Test-Path -LiteralPath $taskVsWhere) {
        $taskVsRoot = & $taskVsWhere -latest -products '*' -property installationPath
        if ($taskVsRoot) {
            $taskRedist = Join-Path $taskVsRoot 'VC/Redist/MSVC'
            $taskRuntime = Get-ChildItem -LiteralPath $taskRedist -Filter 'vcruntime140.dll' -Recurse |
                Where-Object { $_.DirectoryName -match '\\x64\\Microsoft\.VC[^\\]+\.CRT$' } |
                Sort-Object FullName -Descending | Select-Object -First 1
            if ($taskRuntime) { $RuntimeDirectory = $taskRuntime.DirectoryName }
        }
    }
}
if (-not $RuntimeDirectory -or -not (Test-Path -LiteralPath (Join-Path $RuntimeDirectory 'vcruntime140.dll'))) {
    throw '未找到可再分发的 VC++ x64 运行库，请用 -RuntimeDirectory 指定其 CRT 文件夹。'
}

$taskStage = Join-Path $taskRoot ('.work/windows-installer-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $taskStage -Force | Out-Null
Copy-Item -Path (Join-Path $taskRelease '*') -Destination $taskStage -Recurse
Copy-Item -Path (Join-Path $RuntimeDirectory '*.dll') -Destination $taskStage
Copy-Item -LiteralPath (Join-Path $taskRoot 'WINDOWS.md'),(Join-Path $taskRoot 'THIRD_PARTY_NOTICES.md') -Destination $taskStage
$taskOutput = Join-Path $taskRoot 'releases'
New-Item -ItemType Directory -Path $taskOutput -Force | Out-Null
& $Compiler "/DAppVersion=$taskVersion" "/DBundleDir=$taskStage" "/DOutputDir=$taskOutput" (Join-Path $taskRoot 'packaging/windows.iss')
if ($LASTEXITCODE -ne 0) { throw 'EXE 安装包编译失败。' }
Write-Host "安装包：$(Join-Path $taskOutput "meizizi-windows-$taskVersion-setup.exe")"
