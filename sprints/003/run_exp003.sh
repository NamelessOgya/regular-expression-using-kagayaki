#!/usr/bin/env bash
# =============================================================
# sprints/003/run_exp003.sh
# Sprint 003: 理論値と実測値の測定・突合実験スクリプト (レジューム対応)
# =============================================================
set -e

WIKI_FILE="./data/wiki_plain.txt"
PATTERNS_FILE="./sprints/003/patterns_exp003.txt"
OUT_BASE="./results/sprint003_exp"
N_RUNS=3

if [ ! -f "$WIKI_FILE" ]; then
    echo "[ERROR] Target file not found: $WIKI_FILE"
    exit 1
fi

if [ ! -f "$PATTERNS_FILE" ]; then
    echo "[ERROR] Patterns file not found: $PATTERNS_FILE"
    exit 1
fi

# UTF-8 文字数を正確に取得
MAX_CHARS=$(python3 -c "
with open('$WIKI_FILE', encoding='utf-8', errors='ignore') as f:
    print(len(f.read()))
")

echo "=================================================="
echo " Sprint 003: 理論値と実測値の測定・突合実験"
echo " データセット: $WIKI_FILE ($MAX_CHARS chars)"
echo " パターン    : $PATTERNS_FILE"
echo " 試行回数    : $N_RUNS 回"
echo " 出力先      : $OUT_BASE"
echo "=================================================="

# 1. test_cases.csv の安全な差し替え
cp ./data/test_cases.csv ./data/test_cases.csv.bak
cleanup() {
    cp ./data/test_cases.csv.bak ./data/test_cases.csv
    rm -f ./data/test_cases.csv.bak
}
trap cleanup EXIT

echo "正規表現" > ./data/test_cases.csv
cat "$PATTERNS_FILE" >> ./data/test_cases.csv

mkdir -p "$OUT_BASE"

INC="-I./include -I./src/gpu -I./src/gpu/common -I./src/gpu/line_parallel -I./src/gpu/chunk_parallel"
OPT="-O3"

# =============================================================
# ビルド
# =============================================================
echo ""
echo ">>> [1/5] ベンチマークバイナリのビルド"

if [ ! -f "./run_exp003_cpu_o3.out" ]; then
    echo "  [Build] CPU (-O3)..."
    gcc $OPT $INC -c src/cpu/nfa_cpu.c     -o nfa_cpu_o3.o
    gcc $OPT $INC -c src/common/utils.c    -o utils_cpu_o3.o
    gcc $OPT $INC -c src/common/re2post.c  -o re2post_cpu_o3.o
    gcc $OPT $INC -c src/common/post2nfa.c -o post2nfa_cpu_o3.o
    gcc $OPT $INC -c app/run_benchmark.c   -o run_benchmark_cpu_o3.o
    gcc $OPT nfa_cpu_o3.o utils_cpu_o3.o re2post_cpu_o3.o post2nfa_cpu_o3.o run_benchmark_cpu_o3.o -o ./run_exp003_cpu_o3.out
fi

if [ ! -f "./run_exp003_cpu_asan.out" ]; then
    echo "  [Build] CPU (-O1 ASan)..."
    gcc -g -O1 -fsanitize=address $INC -c src/cpu/nfa_cpu.c     -o nfa_cpu_asan.o
    gcc -g -O1 -fsanitize=address $INC -c src/common/utils.c    -o utils_asan.o
    gcc -g -O1 -fsanitize=address $INC -c src/common/re2post.c  -o re2post_asan.o
    gcc -g -O1 -fsanitize=address $INC -c src/common/post2nfa.c -o post2nfa_asan.o
    gcc -g -O1 -fsanitize=address $INC -c app/run_benchmark.c   -o run_benchmark_asan.o
    gcc -fsanitize=address nfa_cpu_asan.o utils_asan.o re2post_asan.o post2nfa_asan.o run_benchmark_asan.o -o ./run_exp003_cpu_asan.out
fi

# GPU 共通オブジェクト
if [ ! -f "./run_exp003_gpu_line.out" ] || [ ! -f "./run_exp003_gpu_chunk.out" ] || [ ! -f "./run_exp003_gpu_dynamic.out" ]; then
    echo "  [Build] GPU Common Objects..."
    nvcc $OPT -arch=sm_80 $INC -c src/gpu/line_parallel/nfa_gpu_line.cu    -o nfa_gpu_line.o
    nvcc $OPT -arch=sm_80 $INC -DLINES_PER_CHUNK=8 -c src/gpu/chunk_parallel/nfa_gpu_chunk.cu -o nfa_gpu_chunk_lpc8.o

    echo "  [Build] GPU Line-Parallel..."
    gcc  $OPT -DGPU_LINE_RUN $INC -c src/cpu/nfa_cpu.c     -o nfa_cpu_gline.o
    gcc  $OPT -DGPU_LINE_RUN $INC -c src/common/utils.c    -o utils_gline.o
    gcc  $OPT -DGPU_LINE_RUN $INC -c src/common/re2post.c  -o re2post_gline.o
    gcc  $OPT -DGPU_LINE_RUN $INC -c src/common/post2nfa.c -o post2nfa_gline.o
    gcc  $OPT -DGPU_LINE_RUN $INC -c app/run_benchmark.c   -o run_benchmark_gline.o
    nvcc $OPT -arch=sm_80 \
        nfa_gpu_line.o nfa_gpu_chunk_lpc8.o nfa_cpu_gline.o \
        utils_gline.o re2post_gline.o post2nfa_gline.o run_benchmark_gline.o \
        -o ./run_exp003_gpu_line.out

    echo "  [Build] GPU Chunk-Parallel Static (LPC=8)..."
    gcc  $OPT -DGPU_CHUNK_RUN $INC -c src/cpu/nfa_cpu.c     -o nfa_cpu_gchunk.o
    gcc  $OPT -DGPU_CHUNK_RUN $INC -c src/common/utils.c    -o utils_gchunk.o
    gcc  $OPT -DGPU_CHUNK_RUN $INC -c src/common/re2post.c  -o re2post_gchunk.o
    gcc  $OPT -DGPU_CHUNK_RUN $INC -c src/common/post2nfa.c -o post2nfa_gchunk.o
    gcc  $OPT -DGPU_CHUNK_RUN $INC -c app/run_benchmark.c   -o run_benchmark_gchunk.o
    nvcc $OPT -arch=sm_80 \
        nfa_gpu_line.o nfa_gpu_chunk_lpc8.o nfa_cpu_gchunk.o \
        utils_gchunk.o re2post_gchunk.o post2nfa_gchunk.o run_benchmark_gchunk.o \
        -o ./run_exp003_gpu_chunk.out

    echo "  [Build] GPU Chunk-Parallel Dynamic..."
    gcc  $OPT -DGPU_CHUNK_DYNAMIC_RUN $INC -c src/cpu/nfa_cpu.c     -o nfa_cpu_gdyn.o
    gcc  $OPT -DGPU_CHUNK_DYNAMIC_RUN $INC -c src/common/utils.c    -o utils_gdyn.o
    gcc  $OPT -DGPU_CHUNK_DYNAMIC_RUN $INC -c src/common/re2post.c  -o re2post_gdyn.o
    gcc  $OPT -DGPU_CHUNK_DYNAMIC_RUN $INC -c src/common/post2nfa.c -o post2nfa_gdyn.o
    gcc  $OPT -DGPU_CHUNK_DYNAMIC_RUN $INC -c app/run_benchmark.c   -o run_benchmark_gdyn.o
    nvcc $OPT -arch=sm_80 \
        nfa_gpu_line.o nfa_gpu_chunk_lpc8.o nfa_cpu_gdyn.o \
        utils_gdyn.o re2post_gdyn.o post2nfa_gdyn.o run_benchmark_gdyn.o \
        -o ./run_exp003_gpu_dynamic.out
fi

echo "[Build] 全バイナリの準備が完了しました。"

# =============================================================
# 実行関数
# =============================================================
run_suite() {
    local name="$1"
    local bin="$2"
    local target_runs="${3:-$N_RUNS}"
    local target_dir="$OUT_BASE/$name"
    mkdir -p "$target_dir"
    echo ""
    echo "=================================================="
    echo "  手法: $name (実行バイナリ: $bin, 試行回数: $target_runs)"
    echo "=================================================="

    for run_i in $(seq 1 "$target_runs"); do
        local out_file="$target_dir/run_${run_i}.csv"
        if [ -f "$out_file" ] && [ -s "$out_file" ]; then
            echo "  --- 試行 $run_i / $target_runs: すでに存在するためスキップ ($out_file) ---"
            continue
        fi

        echo "  --- 試行 $run_i / $target_runs 実行中 ---"
        ls ./results/results_*.csv 2>/dev/null | sort > /tmp/exp003_before.txt || true
        "$bin" "$WIKI_FILE" "$MAX_CHARS" 2>/dev/null || true
        ls ./results/results_*.csv 2>/dev/null | sort > /tmp/exp003_after.txt || true
        NEW_FILE=$(comm -13 /tmp/exp003_before.txt /tmp/exp003_after.txt | head -1 || true)
        if [ -n "$NEW_FILE" ] && [ -f "$NEW_FILE" ]; then
            mv "$NEW_FILE" "$out_file"
            echo "    -> 保存: $out_file"
        else
            echo "    [WARN] 出力 CSV が見つかりませんでした。"
        fi
    done
}

# =============================================================
# 計測実行
# =============================================================
# 1. CPU (-O3): 既に完了済みならスキップされる
run_suite "cpu_o3"             "./run_exp003_cpu_o3.out" 3

# 2. CPU (ASan): オーバーヘッド確認のため 1 回実行
run_suite "cpu_asan"           "./run_exp003_cpu_asan.out" 1

# 3. GPU Line-Parallel (LPC=1): 3 回実行
run_suite "gpu_line"           "./run_exp003_gpu_line.out" 3

# 4. GPU Chunk-Parallel Static (LPC=8): 3 回実行
run_suite "gpu_chunk_static"   "./run_exp003_gpu_chunk.out" 3

# 5. GPU Chunk-Parallel Dynamic: 3 回実行
run_suite "gpu_chunk_dynamic"  "./run_exp003_gpu_dynamic.out" 3

echo ""
echo "=================================================="
echo " Sprint 003 計測完了! 集計・解析スクリプトを実行します..."
echo "=================================================="
python3 sprints/003/analyze_exp003.py
