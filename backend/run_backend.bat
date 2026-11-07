@echo off
title Smart Meeting AI Backend
cd /d "%~dp0"
echo ==============================================
echo   Starting Smart Meeting AI Backend Server
echo ==============================================
echo   Local API:  http://localhost:8000
echo   API Docs:   http://localhost:8000/docs
echo   Health:     http://localhost:8000/health
echo ==============================================
echo.
venv\Scripts\python.exe -m uvicorn main:app --reload --host 0.0.0.0 --port 8000
pause
