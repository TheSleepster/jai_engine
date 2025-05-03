@echo off

IF NOT EXIST ..\build\ mkdir ..\build

jai ../code/main.jai  -llvm -natvis -debugger -very_debug -no_inline -output_path ../build/ -exe game_DEBUG
REM jai ../code/main.jai -natvis -release -output_path ../build/ -exe game_DEBUG
