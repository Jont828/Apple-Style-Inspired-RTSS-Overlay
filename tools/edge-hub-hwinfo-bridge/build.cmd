@echo off
setlocal
rem Builds with the C# compiler that ships with Windows (.NET Framework 4.x); no SDK needed.
set CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe
if not exist "%CSC%" set CSC=%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe
if not exist "%CSC%" (
  echo csc.exe not found. Install .NET Framework 4.x.
  exit /b 1
)
cd /d "%~dp0"
if not exist bin mkdir bin
rem Console build for testing / manual runs.
"%CSC%" /nologo /optimize+ /target:exe /platform:anycpu /out:bin\EdgeHubBridge.exe EdgeHubBridge.cs || exit /b 1
rem Windowless build for running in the background at logon.
"%CSC%" /nologo /optimize+ /target:winexe /platform:anycpu /out:bin\EdgeHubBridgeHidden.exe EdgeHubBridge.cs || exit /b 1
echo Built bin\EdgeHubBridge.exe and bin\EdgeHubBridgeHidden.exe
