#!/usr/bin/env bash
# =============================================================
# run_sweep_gpu.sh  (GPU版)
# GPU Line-Parallel と GPU Chunk-Parallel の2種を1回分スイープする。
#
# 使い方:
#   ./run_sweep_gpu.sh                                  # デフォルト出力先
#   ./run_sweep_gpu.sh ./data/wiki_plain.txt --out ./results/run_xxx/gpu/run1
#
# 出力構造:
#   OUT_DIR/
#     gpu_line/   ← GPU Line-Parallel の結果
#       result_sizeN.csv, manifest.txt, summary.csv
#     gpu_chunk/  ← GPU Chunk-Parallel の結果
#       result_sizeN.csv, manifest.txt, summary.csv
# =============================================================
set -e

# --------------------------------------------------------
# 引数の解析
# --------------------------------------------------------
WIKI_FILE="./data/wiki_plain.txt"
OUT_DIR=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --out) OUT_DIR="$2"; shift 2 ;;
        *) WIKI_FILE="$1"; shift ;;
    esac
done

if [ ! -f "$WIKI_FILE" ]; then
    echo "[ERROR] Target file not found: $WIKI_FILE"
    echo "        Run ./setup_dataset.sh first."
    exit 1
fi

TIMESTAMP=$(date +%Y%m%d_%H_%M_%S)
if [ -z "$OUT_DIR" ]; then
    OUT_DIR="./results/sweep_gpu_${TIMESTAMP}"
fi

DIR_LINE="${OUT_DIR}/gpu_line"
DIR_CHUNK="${OUT_DIR}/gpu_chunk"
DIR_CHUNK_DYN="${OUT_DIR}/gpu_chunk_dynamic"
mkdir -p "$DIR_LINE" "$DIR_CHUNK" "$DIR_CHUNK_DYN"

# UTF-8 文字数を正確に取得
MAX_CHARS=$(python3 -c "
with open('$WIKI_FILE', encoding='utf-8', errors='ignore') as f:
    print(len(f.read()))
")

# サイズリスト: 100 → 1000 → ... → MAX (10倍刻み)
SIZES=()
s=100
while [ "$s" -lt "$MAX_CHARS" ]; do
    SIZES+=("$s")
    s=$((s * 10))
done
SIZES+=("$MAX_CHARS")

BINARY_LINE="./run_benchmark_gpu_line.out"
BINARY_CHUNK="./run_benchmark_gpu_chunk.out"
BINARY_CHUNK_DYN="./run_benchmark_gpu_chunk_dynamic.out"

echo "=================================================="
echo " GPU Benchmark Sweep (Line-Parallel + Chunk-Parallel)"
echo " Target : $WIKI_FILE  (~${MAX_CHARS} chars)"
echo " Sizes  : ${SIZES[*]}"
echo " Out    : $OUT_DIR"
echo "=================================================="

# --------------------------------------------------------
# ビルド
# --------------------------------------------------------
echo ""
echo "[Build] Compiling GPU benchmark binaries..."
INC="-I./include -I./src/gpu -I./src/gpu/common -I./src/gpu/line_parallel -I./src/gpu/chunk_parallel"
OPT="-O3"

# 共有オブジェクト（NFA カーネル、CPU コア）
# utils.c は GPU_LINE_RUN / GPU_CHUNK_RUN / GPU_CHUNK_DYNAMIC_RUN を有効にしてビルド
nvcc $OPT -arch=sm_80 $INC -c src/gpu/line_parallel/nfa_gpu_line.cu    -o nfa_gpu_line.o
nvcc $OPT -arch=sm_80 $INC -c src/gpu/chunk_parallel/nfa_gpu_chunk.cu  -o nfa_gpu_chunk.o
gcc  $OPT -DGPU_LINE_RUN -DGPU_CHUNK_RUN -DGPU_CHUNK_DYNAMIC_RUN $INC -c src/cpu/nfa_cpu.c     -o nfa_cpu_gpu.o
gcc  $OPT -DGPU_LINE_RUN -DGPU_CHUNK_RUN -DGPU_CHUNK_DYNAMIC_RUN $INC -c src/common/utils.c    -o utils_gpu.o
gcc  $OPT -DGPU_LINE_RUN -DGPU_CHUNK_RUN -DGPU_CHUNK_DYNAMIC_RUN $INC -c src/common/re2post.c  -o re2post_gpu.o
gcc  $OPT -DGPU_LINE_RUN -DGPU_CHUNK_RUN -DGPU_CHUNK_DYNAMIC_RUN $INC -c src/common/post2nfa.c -o post2nfa_gpu.o

# Binary 1: Line-Parallel のみ計測
gcc  $OPT -DGPU_LINE_RUN $INC -c app/run_benchmark.c -o run_benchmark_gpu_line.o
nvcc $OPT -arch=sm_80 \
    nfa_gpu_line.o nfa_gpu_chunk.o nfa_cpu_gpu.o \
    utils_gpu.o re2post_gpu.o post2nfa_gpu.o run_benchmark_gpu_line.o \
    -o "$BINARY_LINE"
echo "[Build] OK -> $BINARY_LINE"

# Binary 2: Chunk-Parallel のみ計測
gcc  $OPT -DGPU_CHUNK_RUN $INC -c app/run_benchmark.c -o run_benchmark_gpu_chunk.o
nvcc $OPT -arch=sm_80 \
    nfa_gpu_line.o nfa_gpu_chunk.o nfa_cpu_gpu.o \
    utils_gpu.o re2post_gpu.o post2nfa_gpu.o run_benchmark_gpu_chunk.o \
    -o "$BINARY_CHUNK"
echo "[Build] OK -> $BINARY_CHUNK"

# Binary 3: Chunk-Parallel (Dynamic) のみ計測
gcc  $OPT -DGPU_CHUNK_DYNAMIC_RUN $INC -c app/run_benchmark.c -o run_benchmark_gpu_chunk_dynamic.o
nvcc $OPT -arch=sm_80 \
    nfa_gpu_line.o nfa_gpu_chunk.o nfa_cpu_gpu.o \
    utils_gpu.o re2post_gpu.o post2nfa_gpu.o run_benchmark_gpu_chunk_dynamic.o \
    -o "$BINARY_CHUNK_DYN"
echo "[Build] OK -> $BINARY_CHUNK_DYN"

# --------------------------------------------------------
# サイズごとに実行（Line-Parallel）
# --------------------------------------------------------
echo ""
echo "--- [GPU Line-Parallel] Sweeping ---"
mkdir -p "./results"

MANIFEST_LINE="${DIR_LINE}/manifest.txt"
> "$MANIFEST_LINE"

for size in "${SIZES[@]}"; do
    echo ""
    echo "  [GPU Line] size = ${size} chars"

    ls ./results/results_*.csv 2>/dev/null | sort > /tmp/sweep_gline_before.txt || true
    "$BINARY_LINE" "$WIKI_FILE" "$size" || true   # CUDA atexit crash は無視
    ls ./results/results_*.csv 2>/dev/null | sort > /tmp/sweep_gline_after.txt || true
    NEW_FILE=$(comm -13 /tmp/sweep_gline_before.txt /tmp/sweep_gline_after.txt | head -1 || true)

    if [ -z "$NEW_FILE" ]; then
        NEW_FILE=$(ls -t ./results/results_*.csv 2>/dev/null | head -1 || true)
        echo "[WARN] Could not detect new file; using latest: $NEW_FILE"
    fi

    if [ -n "$NEW_FILE" ]; then
        DEST="${DIR_LINE}/result_size${size}.csv"
        cp "$NEW_FILE" "$DEST"
        echo "${DEST}:${size}" >> "$MANIFEST_LINE"
        echo "  [GPU Line] Saved -> $DEST"
    fi
done

python3 /app/scripts/aggregate_sweep.py "$MANIFEST_LINE" "${DIR_LINE}/summary.csv"
echo "[GPU Line] Summary -> ${DIR_LINE}/summary.csv"

# --------------------------------------------------------
# サイズごとに実行（Chunk-Parallel）
# --------------------------------------------------------
echo ""
echo "--- [GPU Chunk-Parallel] Sweeping ---"

MANIFEST_CHUNK="${DIR_CHUNK}/manifest.txt"
> "$MANIFEST_CHUNK"

for size in "${SIZES[@]}"; do
    echo ""
    echo "  [GPU Chunk] size = ${size} chars"

    ls ./results/results_*.csv 2>/dev/null | sort > /tmp/sweep_gchunk_before.txt || true
    "$BINARY_CHUNK" "$WIKI_FILE" "$size" || true   # CUDA atexit crash は無視
    ls ./results/results_*.csv 2>/dev/null | sort > /tmp/sweep_gchunk_after.txt || true
    NEW_FILE=$(comm -13 /tmp/sweep_gchunk_before.txt /tmp/sweep_gchunk_after.txt | head -1 || true)

    if [ -z "$NEW_FILE" ]; then
        NEW_FILE=$(ls -t ./results/results_*.csv 2>/dev/null | head -1 || true)
        echo "[WARN] Could not detect new file; using latest: $NEW_FILE"
    fi

    if [ -n "$NEW_FILE" ]; then
        DEST="${DIR_CHUNK}/result_size${size}.csv"
        cp "$NEW_FILE" "$DEST"
        echo "${DEST}:${size}" >> "$MANIFEST_CHUNK"
        echo "  [GPU Chunk] Saved -> $DEST"
    fi
done

python3 /app/scripts/aggregate_sweep.py "$MANIFEST_CHUNK" "${DIR_CHUNK}/summary.csv"
echo "[GPU Chunk] Summary -> ${DIR_CHUNK}/summary.csv"

# --------------------------------------------------------
# サイズごとに実行（Chunk-Parallel Dynamic）
# --------------------------------------------------------
echo ""
echo "--- [GPU Chunk-Parallel Dynamic] Sweeping ---"

MANIFEST_CHUNK_DYN="${DIR_CHUNK_DYN}/manifest.txt"
> "$MANIFEST_CHUNK_DYN"

for size in "${SIZES[@]}"; do
    echo ""
    echo "  [GPU Chunk Dynamic] size = ${size} chars"

    ls ./results/results_*.csv 2>/dev/null | sort > /tmp/sweep_gchunkdyn_before.txt || true
    "$BINARY_CHUNK_DYN" "$WIKI_FILE" "$size" || true   # CUDA atexit crash は無視
    ls ./results/results_*.csv 2>/dev/null | sort > /tmp/sweep_gchunkdyn_after.txt || true
    NEW_FILE=$(comm -13 /tmp/sweep_gchunkdyn_before.txt /tmp/sweep_gchunkdyn_after.txt | head -1 || true)

    if [ -z "$NEW_FILE" ]; then
        NEW_FILE=$(ls -t ./results/results_*.csv 2>/dev/null | head -1 || true)
        echo "[WARN] Could not detect new file; using latest: $NEW_FILE"
    fi

    if [ -n "$NEW_FILE" ]; then
        DEST="${DIR_CHUNK_DYN}/result_size${size}.csv"
        cp "$NEW_FILE" "$DEST"
        echo "${DEST}:${size}" >> "$MANIFEST_CHUNK_DYN"
        echo "  [GPU Chunk Dynamic] Saved -> $DEST"
    fi
done

python3 /app/scripts/aggregate_sweep.py "$MANIFEST_CHUNK_DYN" "${DIR_CHUNK_DYN}/summary.csv"
echo "[GPU Chunk Dynamic] Summary -> ${DIR_CHUNK_DYN}/summary.csv"

echo ""
echo "=================================================="
echo " GPU Sweep complete!"
echo "  Line    : ${DIR_LINE}/summary.csv"
echo "  Chunk   : ${DIR_CHUNK}/summary.csv"
echo "  Dynamic : ${DIR_CHUNK_DYN}/summary.csv"
echo "=================================================="
