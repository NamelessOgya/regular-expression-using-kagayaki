#!/usr/bin/env bash
set -e

INC="-I./include -I./src/gpu"
CFLAGS="-O3 -DGPU_RUN"

echo "Compiling nfa_gpu.cu..."
# GPU側のコンパイル (オブジェクトファイルを生成)
nvcc -O3 -arch=sm_80 $INC -c src/gpu/nfa_gpu.cu -o nfa_gpu.o

echo "Compiling utils.c..."
gcc $CFLAGS $INC -c src/common/utils.c -o utils.o

echo "Compiling run_benchmark.c..."
gcc $CFLAGS $INC -c app/run_benchmark.c -o run_benchmark.o

echo "Linking..."
# 最終リンクはnvccで行うか、gccでCUDARTをリンクする
nvcc -O3 -arch=sm_80 nfa_gpu.o utils.o run_benchmark.o -o run_benchmark_gpu.out

echo "Running Benchmark..."
./run_benchmark_gpu.out