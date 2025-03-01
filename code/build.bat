@echo off

IF NOT EXIST ..\build\ mkdir ..\build

jai ../code/main.jai -natvis -very_debug -no_inline
REM jai ../code/main.jai -natvis -release
copy *.exe ..\build\
copy *.pdb ..\build\

del *.exe
del *.pdb

@echo ====================
@echo Compilation Complete
@echo ====================
