# Create source and Windows archives from an explicit allow-list.
$ErrorActionPreference = 'Stop'
$taskRoot = $PSScriptRoot
$distRoot = Join-Path $taskRoot 'dist'
$sourceRoot = Join-Path $distRoot 'RobotTrajectoryLab_Source'
$windowsRoot = Join-Path $distRoot 'RobotTrajectoryLab_Windows'
New-Item -ItemType Directory -Path $windowsRoot -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $taskRoot 'packaging/Start_RobotTrajectoryLab.cmd') -Destination $windowsRoot -Force
Copy-Item -LiteralPath (Join-Path $taskRoot 'packaging/README_Runtime.txt') -Destination $windowsRoot -Force
Copy-Item -LiteralPath (Join-Path $taskRoot 'build/standalone/requiredMCRProducts.txt') -Destination $windowsRoot -Force
Copy-Item -LiteralPath (Join-Path $taskRoot 'build/standalone/readme.txt') -Destination (Join-Path $windowsRoot 'runtime_readme.txt') -Force
New-Item -ItemType Directory -Path $sourceRoot -Force | Out-Null
$sourceItems = @('+rtl','assets','docs','examples','tests','packaging','main.m','RobotTrajectoryLab.m','build_release.m','package_release.ps1','run_tests.m','validate_ui.m','README.md')
foreach ($item in $sourceItems) {
    Copy-Item -LiteralPath (Join-Path $taskRoot $item) -Destination $sourceRoot -Recurse -Force
}
$evidenceRoot = Join-Path $sourceRoot 'results/validation'
New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $taskRoot 'results/validation/test_results.csv') -Destination $evidenceRoot -Force
Copy-Item -LiteralPath (Join-Path $taskRoot 'results/validation/screenshots') -Destination $evidenceRoot -Recurse -Force
Copy-Item -LiteralPath (Join-Path $taskRoot 'results/examples') -Destination (Join-Path $sourceRoot 'results') -Recurse -Force
New-Item -ItemType Directory -Path (Join-Path $sourceRoot 'experiments') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $taskRoot 'experiments/example_project.mat') -Destination (Join-Path $sourceRoot 'experiments') -Force
$deploymentRoot = Join-Path $sourceRoot 'results/deployment'
New-Item -ItemType Directory -Path $deploymentRoot -Force | Out-Null
$deploymentEvidence = Join-Path $taskRoot 'build/exe_validation'
if (-not (Test-Path -LiteralPath $deploymentEvidence)) {
    $deploymentEvidence = Join-Path $taskRoot 'results/deployment'
}
foreach ($file in @('selftest_report.json','standalone_arm.png','standalone_mobile.png')) {
    Copy-Item -LiteralPath (Join-Path $deploymentEvidence $file) -Destination $deploymentRoot -Force
}
Copy-Item -LiteralPath (Join-Path $taskRoot 'build/standalone/RobotTrajectoryLab.exe') -Destination (Join-Path $distRoot 'RobotTrajectoryLab_Windows') -Force
Compress-Archive -LiteralPath $sourceRoot -DestinationPath (Join-Path $distRoot 'RobotTrajectoryLab_V1.0_Source.zip') -Force
Compress-Archive -LiteralPath (Join-Path $distRoot 'RobotTrajectoryLab_Windows') -DestinationPath (Join-Path $distRoot 'RobotTrajectoryLab_V1.0_Windows.zip') -Force
$releaseFiles = Get-ChildItem -LiteralPath $distRoot -File | Where-Object {
    $_.Name -in @('RobotTrajectoryLab_V1.0_Source.zip','RobotTrajectoryLab_V1.0_Windows.zip') -or $_.Extension -eq '.pdf'
}
$releaseFiles += Get-ChildItem -LiteralPath (Join-Path $distRoot 'installer') -File -Filter '*.exe'
$manifest = foreach ($file in $releaseFiles) {
    $relative = $file.FullName.Substring($distRoot.Length+1).Replace('\','/')
    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  $relative"
}
$utf8Encoding = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllLines((Join-Path $distRoot 'SHA256SUMS.txt'),[string[]]$manifest,$utf8Encoding)
$submissionItems = @(
    (Join-Path $distRoot 'RobotTrajectoryLab_V1.0_Source.zip'),
    (Join-Path $distRoot 'RobotTrajectoryLab_V1.0_Windows.zip'),
    (Join-Path $distRoot 'installer'),
    (Join-Path $distRoot 'SHA256SUMS.txt'),
    (Join-Path $distRoot 'SUBMISSION_README.txt')
)
$submissionItems += (Get-ChildItem -LiteralPath $distRoot -File -Filter '*.pdf').FullName
Compress-Archive -LiteralPath $submissionItems -DestinationPath (Join-Path $distRoot 'RobotTrajectoryLab_V1.0_Submission.zip') -Force
Write-Output 'RELEASE_ARCHIVES_COMPLETE'
