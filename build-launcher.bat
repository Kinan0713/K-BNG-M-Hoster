@echo off
setlocal
set CSC=C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe

if not exist "%CSC%" (
    echo Error: C# compiler csc.exe not found at %CSC%
    exit /b 1
)

echo Compiling K-BNG-M-Hoster.exe with embedded icon and assembly metadata...
"%CSC%" /target:winexe ^
    /out:"K-BNG-M-Hoster.exe" ^
    /win32icon:"app.ico" ^
    /optimize+ ^
    /platform:anycpu ^
    /r:System.dll ^
    /r:System.Windows.Forms.dll ^
    Launcher.cs

if %ERRORLEVEL% EQU 0 (
    echo =======================================================
    echo  BUILD SUCCESSFUL: K-BNG-M-Hoster.exe is ready!
    echo =======================================================
) else (
    echo Build failed with error %ERRORLEVEL%.
    exit /b %ERRORLEVEL%
)
