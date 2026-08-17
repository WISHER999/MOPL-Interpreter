#!/bin/bash
# Build script — run this on a real Mac (Apple Silicon) with Xcode CLT installed.
set -e

as -o mopl.o mopl_backend.s
ld -o mopl mopl.o -lSystem -syslibroot "$(xcrun -sdk macosx --show-sdk-path)"

echo "Built ./mopl"
echo "Try it:  ./mopl run examples/hello.mopl"
