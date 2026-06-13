#!/usr/bin/env bash
set -e

INC="-I./include -I./src/gpu -I./src/gpu/common -I./src/gpu/line_parallel -I./src/gpu/chunk_parallel"
CFLAGS="-g -O1 -fsanitize=address -fno-omit-frame-pointer -Wall -Wextra"
LDFLAGS="-fsanitize=address"

echo "=== Compiling (CPU with ASan) ==="
gcc $INC $CFLAGS -c src/cpu/nfa_cpu.c      -o nfa_cpu.o
gcc $INC $CFLAGS -c src/common/utils.c     -o utils.o
gcc $INC $CFLAGS -c src/common/re2post.c   -o re2post.o
gcc $INC $CFLAGS -c src/common/post2nfa.c  -o post2nfa.o
gcc $INC $CFLAGS -c app/run_benchmark.c    -o run_benchmark.o

echo "=== Linking ==="
gcc $LDFLAGS nfa_cpu.o utils.o re2post.o post2nfa.o run_benchmark.o -o run_benchmark.asan

echo "=== Running Benchmark (CPU) ==="
./run_benchmark.asan
