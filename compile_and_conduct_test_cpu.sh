#!/usr/bin/env bash
set -e

INC="-I./include"
# デバッグ＋ASan 用フラグ
CFLAGS="-g -O1 -fsanitize=address -fno-omit-frame-pointer -Wall -Wextra"
LDFLAGS="-fsanitize=address"

echo "Compiling nfa_cpu.c..."
gcc $INC $CFLAGS -c src/cpu/nfa_cpu.c -o nfa_cpu.o

echo "Compiling utils.c..."
gcc $INC $CFLAGS -c src/common/utils.c -o utils.o

echo "Compiling run_benchmark.c..."
gcc $INC $CFLAGS -c app/run_benchmark.c -o run_benchmark.o

echo "Linking..."
gcc $LDFLAGS nfa_cpu.o utils.o run_benchmark.o -o run_benchmark.asan

echo "Running Benchmark..."
chmod +x run_benchmark.asan
./run_benchmark.asan
