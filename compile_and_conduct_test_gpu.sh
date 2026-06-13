#!/usr/bin/env bash
set -e

INC="-I./include -I./src/gpu -I./src/gpu/common -I./src/gpu/line_parallel -I./src/gpu/chunk_parallel"
OPT="-O3"

echo "=== Compiling (GPU Comparison) ==="
nvcc $OPT -arch=sm_80 -DGPU_RUN $INC -c src/gpu/line_parallel/nfa_gpu_line.cu   -o nfa_gpu_line.o
nvcc $OPT -arch=sm_80 -DGPU_RUN $INC -c src/gpu/chunk_parallel/nfa_gpu_chunk.cu -o nfa_gpu_chunk.o
gcc  $OPT             -DGPU_RUN $INC -c src/cpu/nfa_cpu.c                        -o nfa_cpu_gpu.o
gcc  $OPT             -DGPU_RUN $INC -c src/common/utils.c                       -o utils_gpu.o
gcc  $OPT             -DGPU_RUN $INC -c src/common/re2post.c                     -o re2post_gpu.o
gcc  $OPT             -DGPU_RUN $INC -c src/common/post2nfa.c                    -o post2nfa_gpu.o
gcc  $OPT             -DGPU_RUN $INC -c app/run_benchmark.c                      -o run_benchmark_gpu.o

echo "=== Linking ==="
nvcc $OPT -arch=sm_80 \
  nfa_gpu_line.o nfa_gpu_chunk.o nfa_cpu_gpu.o \
  utils_gpu.o re2post_gpu.o post2nfa_gpu.o run_benchmark_gpu.o \
  -o run_benchmark_gpu.out

echo "=== Running Benchmark (GPU) ==="
./run_benchmark_gpu.out