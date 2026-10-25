@echo off
setlocal
cd /d "%~dp0"
"%~dp0RobotTrajectoryLab.exe" --gui "%~dp0Data"
if not "%ERRORLEVEL%"=="0" (
  echo RobotTrajectoryLab could not start. Install MATLAB Runtime R2025a for Windows x64.
  pause
)
endlocal
