#!/bin/bash

pushd ../build
~/.jai/bin/jai-linux ../code/main.jai -llvm -natvis -very_debug -no_inline -output_path ../build/ -exe game_DEBUG.out
#~/.jai/bin/jai-linux ../code/main.jai -natvis -release -output_path ../build/ -exe game_DEBUG.out

# Check for compilation success
if [ $? -ne 0 ]; then
    echo "==================="
    echo "Compilation Failure"
    echo "==================="
    exit 1
fi

# Return to the original directory
popd || exit 1

echo "===================="
echo "Compilation Complete"
echo "===================="
