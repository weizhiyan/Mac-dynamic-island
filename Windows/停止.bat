@echo off
chcp 65001 >nul
title 灵动岛 - 停止

taskkill /IM DynamicIsland.exe /F >nul 2>nul
if errorlevel 1 (echo 灵动岛当前没有在运行。) else (echo 已停止灵动岛。)

timeout /t 2 >nul
