$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$folder = Join-Path $taskRoot 'build/launcher'
# Simulate a session that predates Runtime installation.
$env:PATH = (($env:PATH -split ';') | Where-Object { $_ -notmatch 'MATLAB' }) -join ';'
$clock = [System.Diagnostics.Stopwatch]::StartNew()
$process = Start-Process -FilePath (Join-Path $folder 'RobotTrajectoryLab.exe') -ArgumentList @('--launcher-check','../launcher_startup') -WorkingDirectory $folder -WindowStyle Normal -PassThru
$null = $process.Handle
Write-Output ('LAUNCHER_STARTED PID='+$process.Id)
while (-not $process.WaitForExit(1000)) {
    if ($clock.Elapsed.TotalSeconds -gt 180) {
        Stop-Process -Id $process.Id -Force
        throw 'Launcher validation timed out'
    }
}
$process.WaitForExit()
if ($process.ExitCode -ne 0) { throw ('Launcher exit code '+$process.ExitCode) }
$reportFolder = Join-Path $taskRoot 'build/launcher_startup'
$report = Get-Content -LiteralPath (Join-Path $reportFolder 'startup_report.json') -Raw -Encoding utf8 | ConvertFrom-Json
if (-not ($report.success -and $report.windowVisible -and $report.guiAndTimerReleased -and $report.isDeployed)) { throw 'Launcher did not produce a visible GUI' }
if ($report.runtimeRoot -notlike '*MATLAB Runtime*') { throw 'Launcher used the wrong Runtime' }
@{success=$true;case='launcher_without_runtime_path';elapsed_s=$clock.Elapsed.TotalSeconds;runtimeRoot=$report.runtimeRoot} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $reportFolder 'validation.json') -Encoding utf8
Write-Output ('LAUNCHER_OK elapsed_s='+[math]::Round($clock.Elapsed.TotalSeconds,2))
