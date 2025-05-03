#!/bin/bash

pushd ../build
~/.jai/bin/jai-linux ../code/main.jai -llvm -natvis -very_debug -no_inline -no_color -output_path ../build/ -exe game_DEBUG.out
#~/.jai/bin/jai-linux ../code/main.jai -natvis -release -output_path ../build/ -exe game_DEBUG.out
