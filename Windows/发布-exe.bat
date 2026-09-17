@echo off
chcp 65001 >nul
setlocal
title 灵动岛 - 一键发布独立exe

echo.
echo ============================================
echo   灵动岛 一键发布（生成独立 exe）
echo ============================================
echo.

cd /d "%~dp0"

echo [1/3] 检查 .NET 8 SDK ...
where dotnet >nul 2>nul
if errorlevel 1 (
    echo [错误] 未检测到 dotnet，请先安装 .NET 8 SDK：
    echo   https://dotnet.microsoft.com/download/dotnet/8.0
    echo.
    pause
    exit /b 1
)

echo [2/3] 发布中(单文件、自包含、免装运行时)...
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true

if errorlevel 1 (
    echo.
    echo [错误] 发布失败，请把上面的报错截图发我排查。
    pause
    exit /b 1
)

echo.
echo [3/3] 发布完成！
echo.
set OUT=%~dp0bin\Release\net8.0-windows\win-x64\publish
echo   生成的 exe 位于：
echo   %OUT%\DynamicIsland.exe
echo.

explorer "%OUT%"

echo. 双击 DynamicIsland.exe 即可运行（独立版，无需安装运行时）。
echo.
pause
endlocal