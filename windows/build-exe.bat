@echo off
rem Builds dist\SystemController.exe (one file, no console). Run on Windows.
cd /d "%~dp0"
if not exist .venv py -3 -m venv .venv
.venv\Scripts\python -m pip install -r requirements.txt pyinstaller || goto :eof
.venv\Scripts\pyinstaller --noconfirm --onefile --windowed --name SystemController ^
    --add-data "syscontrol\sprites;sprites" --collect-submodules zeroconf launcher.py
echo.
echo Built dist\SystemController.exe
