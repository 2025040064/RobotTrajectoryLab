$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
Push-Location $taskRoot
try {
    New-Item -ItemType Directory -Path build/launcher/app -Force | Out-Null
    $compilerPath = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
    & $compilerPath /nologo /target:winexe /platform:x64 /optimize+ /codepage:65001 /reference:System.Drawing.dll /reference:System.Windows.Forms.dll /out:build\launcher\RobotTrajectoryLab.exe .\packaging\WindowsLauncher.cs
    if ($LASTEXITCODE -ne 0) { throw 'Windows launcher build failed' }
    Copy-Item -LiteralPath build/standalone/RobotTrajectoryLab.exe -Destination build/launcher/app/RobotTrajectoryLab.exe -Force
} finally { Pop-Location }
