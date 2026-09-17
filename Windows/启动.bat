@echo off
chcp 65001 >nul
setlocal
title 灵动岛 - 一键启动

cd /d "%~dp0"

set "CONFIG=Release"
if /i "%~1"=="debug" set "CONFIG=Debug"

set "EXE=%~dp0bin\%CONFIG%\net8.0-windows\DynamicIsland.exe"
set "PUBLISHED=%~dp0bin\Release\net8.0-windows\win-x64\publish\DynamicIsland.exe"

echo.
echo ==========================================
echo    灵动岛 · 一键启动（Windows 版）
echo ==========================================
echo.

where dotnet >nul 2>nul
if errorlevel 1 goto :no_dotnet

echo [1/3] 关闭正在运行的旧实例 ...
taskkill /IM DynamicIsland.exe /F >nul 2>nul
if errorlevel 1 (echo        · 没有正在运行的实例) else (echo        · 已关闭旧实例，避免出现两个托盘图标)

echo [2/3] 编译（%CONFIG%）...
dotnet build -c %CONFIG% --nologo -v minimal
if errorlevel 1 goto :build_failed

if not exist "%EXE%" goto :exe_missing

echo [3/3] 启动 ...
start "" "%EXE%"
echo.
echo 完成：灵动岛已在系统托盘启动，没有任务栏按钮。
echo   展开 = 鼠标移到屏幕顶部中间的小胶囊上
echo   退出 = 右键托盘图标 - 退出（或运行 停止.bat）
echo.
timeout /t 3 >nul
exit /b 0

:no_dotnet
if exist "%PUBLISHED%" (
    echo [提示] 未检测到 .NET SDK，改为直接启动已经发布好的独立版。
    echo.
    start "" "%PUBLISHED%"
    timeout /t 3 >nul
    exit /b 0
)
echo [错误] 未检测到 dotnet，请先安装 .NET 8 SDK：
echo        https://dotnet.microsoft.com/download/dotnet/8.0
echo.
pause
exit /b 1

:build_failed
echo.
echo [错误] 编译失败，请把上面的报错发我排查。
echo.
pause
exit /b 1

:exe_missing
echo.
echo [错误] 编译通过但没有找到可执行文件：
echo        %EXE%
echo.
pause
exit /b 1
