@echo off
rem Builds the 32-bit ddraw.dll fix proxy (patch\gnomefix.c) into patch\out\ddraw.dll.
rem Requires Visual Studio Build Tools (x86 C compiler).
setlocal
set VCVARS=C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars32.bat
if not exist "%VCVARS%" set VCVARS=C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars32.bat
call "%VCVARS%" >nul || exit /b 1
if not exist "%~dp0out" mkdir "%~dp0out"
pushd "%~dp0out"
cl /nologo /O1 /GS- /LD ..\gnomefix.c /link /DEF:..\gnomefix.def /OUT:ddraw.dll user32.lib gdi32.lib kernel32.lib winmm.lib
set RC=%ERRORLEVEL%
popd
exit /b %RC%
