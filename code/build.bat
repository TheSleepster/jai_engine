@echo off

IF NOT EXIST ..\build\ mkdir ..\build

jai ../code/main.jai  -llvm -natvis  -debugger -very_debug -no_inline -no_backtrace_on_crash -output_path ../build/ -exe game_DEBUG
REM jai ../code/main.jai -natvis -release -output_path ../build/ -exe game_DEBUG.exe

@echo ====================
@echo Compilation Complete
@echo ====================
