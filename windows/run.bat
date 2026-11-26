@echo off
rem Runs the System Controller companion from source. Needs Python 3.13 or newer from python.org (with Tk).
cd /d "%~dp0"
if not exist .venv (
    py -3 -m venv .venv || goto :nopython
    .venv\Scripts\python -m pip install --upgrade pip >nul
    .venv\Scripts\python -m pip install -r requirements.txt || goto :eof
)
start "" .venv\Scripts\pythonw -m syscontrol
goto :eof
:nopython
echo Python 3.13 or newer is needed: https://www.python.org/downloads/windows/
pause
