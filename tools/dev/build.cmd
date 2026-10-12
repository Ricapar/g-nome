@echo off
rem Builds the 32-bit diagnostic tools in tools\dev (outputs are gitignored).
rem   gtrace.dll      IAT-hook tracer for GDI/USER calls (log: gtrace.log next to the DLL)
rem   inject.exe      inject <pid> <dll>  - LoadLibraryA a DLL into the running game
rem   peek.exe        peek <pid> <module> <offhex> <ndwords> [deref...]  - read game memory
rem   stacksample.exe stacksample <pid> [samples] [ms]  - EBP-chain stack samples of all threads
setlocal
set VCVARS=C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars32.bat
if not exist "%VCVARS%" set VCVARS=C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars32.bat
call "%VCVARS%" >nul || exit /b 1
pushd "%~dp0"
cl /nologo /O1 /LD gtrace.c user32.lib gdi32.lib /Fe:gtrace.dll || goto :fail
cl /nologo /O1 inject.c || goto :fail
cl /nologo /O1 peek.c psapi.lib || goto :fail
cl /nologo /O1 stacksample.c psapi.lib || goto :fail
popd
exit /b 0
:fail
popd
exit /b 1
