#!/usr/bin/env bash
set -e

INC="-I./include"
CFLAGS="-g -Wall -Wextra"

echo "Compiling nfa_cpu.c and test_unit_nfa.c..."
gcc $INC $CFLAGS src/cpu/nfa_cpu.c tests/test_unit_nfa.c -o test_unit.out

echo "Running Unit Tests..."
./test_unit.out
