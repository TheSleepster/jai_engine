#!/bin/bash

pushd ../build
../../bin/jai-linux ../code/main.jai -llvm -natvis -very_debug - no_inline -output_path../../build/

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
