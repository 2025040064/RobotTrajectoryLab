# Validate the GUI build against the installed Runtime, without development DLLs.
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
$appFolder = Join-Path $taskRoot 'build/standalone'
$appPath = Join-Path $appFolder 'RobotTrajectoryLab.exe'
$runtimeInfo = Get-ItemProperty 'HKLM:/SOFTWARE/MathWorks/MATLAB Runtime/25.1'
$runtimeRoot = $runtimeInfo.MATLABROOT.TrimEnd('\','/')
if (-not (Test-Path -LiteralPath $runtimeRoot)) { throw 'Installed Runtime was not found' }
$env:PATH = (($env:PATH -split ';') | Where-Object { $_ -notmatch 'MATLAB1' }) -join ';'
# This Codex session predates the Runtime installation; use only installed Runtime DLLs.
$runtimeBins = @('runtime/win64','bin/win64','sys/os/win64') | ForEach-Object { Join-Path $runtimeRoot $_ }
$env:PATH = ($runtimeBins -join ';')+';'+$env:PATH
foreach ($case in @('startup','gui')) {
    $folder = Join-Path $taskRoot ('build/installed_runtime_'+$case)
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    $env:MCR_CACHE_ROOT = Join-Path $taskRoot ('build/runtime_cache_v101_'+$case)
    $mode = if ($case -eq 'startup') { '--startup-check' } else { '--gui-smoke' }
    $clock = [System.Diagnostics.Stopwatch]::StartNew()
    $process = Start-Process -FilePath $appPath -ArgumentList @($mode,('../installed_runtime_'+$case)) -WorkingDirectory $appFolder -WindowStyle Normal -PassThru
    Write-Output ('VALIDATION_STARTED: '+$case+' PID='+$process.Id)
    while (-not $process.WaitForExit(1000)) {
        if ($clock.Elapsed.TotalSeconds -gt 240) {
            Stop-Process -Id $process.Id -Force
            throw ('Validation timed out: '+$case)
        }
    }
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw ('Application exit code '+$process.ExitCode+' in '+$case) }
    $reportName = if ($case -eq 'startup') { 'startup_report.json' } else { 'selftest_report.json' }
    $report = Get-Content -LiteralPath (Join-Path $folder $reportName) -Raw -Encoding utf8 | ConvertFrom-Json
    if (-not ($report.success -and $report.isDeployed -and $report.guiAndTimerReleased)) { throw ('Validation did not pass: '+$case) }
    if ($report.runtimeRoot.TrimEnd('\','/') -ne $runtimeRoot) { throw ('Wrong Runtime used: '+$report.runtimeRoot) }
    if ($case -eq 'startup' -and -not $report.windowVisible) { throw 'GUI window was not visible' }
    $timing = @{case=$case;elapsed_s=$clock.Elapsed.TotalSeconds;runtimeRoot=$report.runtimeRoot;exitCode=$process.ExitCode;success=$true}
    $timing | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $folder 'validation.json') -Encoding utf8
    Write-Output ('VALIDATION_OK: '+$case+' elapsed_s='+[math]::Round($clock.Elapsed.TotalSeconds,2))
}
