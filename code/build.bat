@echo off

IF NOT EXIST ..\build\ mkdir ..\build

REM jai ../code/main.jai      -llvm -natvis -debugger -very_debug -no_inline -output_path ../build/ -exe game_DEBUG
REM jai ../code/main.jai -llvm -natvis -release -output_path ../build/ -exe game_DEBUG

jai build.jai
