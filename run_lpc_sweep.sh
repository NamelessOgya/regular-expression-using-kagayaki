#!/usr/bin/env bash
# =============================================================
# run_lpc_sweep.sh  - LINES_PER_CHUNK スイープ
#
# LINES_PER_CHUNK の値を変えながら GPU Chunk-Parallel をビルド・実行し、
# 各 N での sweep 結果を OUT_DIR/lpc_N/ に保存する。
#
# 使い方:
#   ./run_lpc_sweep.sh ./data/wiki_plain.txt --out ./results/run_xxx/lpc_sweep \
#       --lpc 1 2 4 8 16 32
#
# 出力構造:
#   OUT_DIR/
#     lpc_1/  run1/ run2/ run3/ → summary.csv
#     lpc_4/  ...
#     lpc_8/  ...
#     ...
# =============================================================
set -e

# --------------------------------------------------------
# 引数の解析
# --------------------------------------------------------
WIKI_FILE="./data/wiki_plain.txt"
OUT_DIR=""
N_RUNS=3
LPC_VALUES=()
PARSE_LPC=0
IS_DYNAMIC=0

while [[ $# -gt 0 ]]; do
    case $1 in
        --out)     OUT_DIR="$2"; shift 2 ;;
        --runs)    N_RUNS="$2"; shift 2 ;;
        --dynamic) IS_DYNAMIC=1; shift ;;
        --lpc)     PARSE_LPC=1; shift ;;
        *)
            if [ "$PARSE_LPC" -eq 1 ]; then
                # 数字ならLPC値として追加、それ以外でLPCパース終了
                if [[ "$1" =~ ^[0-9]+$ ]]; then
                    LPC_VALUES+=("$1"); shift
                else
                    PARSE_LPC=0; WIKI_FILE="$1"; shift
                fi
            else
                WIKI_FILE="$1"; shift
            fi ;;
    esac
done

# デフォルト LPC 値
if [ ${#LPC_VALUES[@]} -eq 0 ]; then
    LPC_VALUES=(1 2 4 8 16 32)
fi

TIMESTAMP=$(date +%Y%m%d_%H_%M_%S)
if [ -z "$OUT_DIR" ]; then
    OUT_DIR="./results/lpc_sweep_${TIMESTAMP}"
fi

if [ ! -f "$WIKI_FILE" ]; then
    echo "[ERROR] Target file not found: $WIKI_FILE"; exit 1
fi

echo "=================================================="
echo " LINES_PER_CHUNK Sweep"
echo " Target : $WIKI_FILE"
echo " LPC    : ${LPC_VALUES[*]}"
echo " Runs   : $N_RUNS"
echo " Out    : $OUT_DIR"
echo "=================================================="

INC="-I./include -I./src/gpu -I./src/gpu/common -I./src/gpu/line_parallel -I./src/gpu/chunk_parallel"
OPT="-O3"

# 共有オブジェクト（NFA カーネル、CPU コア）は 1 回だけビルド
echo ""
echo "[Build] Shared objects..."
MACRO="-DGPU_CHUNK_RUN"
if [ "$IS_DYNAMIC" -eq 1 ]; then
    MACRO="-DGPU_CHUNK_DYNAMIC_RUN"
fi

nvcc $OPT -arch=sm_80 $INC -c src/gpu/line_parallel/nfa_gpu_line.cu  -o nfa_gpu_line.o
gcc  $OPT $MACRO $INC -c src/cpu/nfa_cpu.c                  -o nfa_cpu_gpu.o
gcc  $OPT $MACRO $INC -c src/common/utils.c                 -o utils_gpu.o
gcc  $OPT $MACRO $INC -c src/common/re2post.c               -o re2post_gpu.o
gcc  $OPT $MACRO $INC -c src/common/post2nfa.c              -o post2nfa_gpu.o
gcc  $OPT $MACRO $INC -c app/run_benchmark.c                -o run_benchmark_gpu_chunk.o
echo "[Build] Shared objects OK ($MACRO)"

# --------------------------------------------------------
# LPC 値ごとにビルド＆sweep
# --------------------------------------------------------
for LPC in "${LPC_VALUES[@]}"; do
    echo ""
    echo "=================================================="
    echo " [LPC=$LPC] Building chunk binary..."
    echo "=================================================="

    # LPC 値を埋め込んでカーネルをビルド
    nvcc $OPT -arch=sm_80 $INC \
        -DLINES_PER_CHUNK=${LPC} \
        -c src/gpu/chunk_parallel/nfa_gpu_chunk.cu \
        -o nfa_gpu_chunk_lpc${LPC}.o

    if [ "$IS_DYNAMIC" -eq 1 ]; then
        BINARY="./run_benchmark_gpu_chunk_dynamic_lpc${LPC}.out"
    else
        BINARY="./run_benchmark_gpu_chunk_lpc${LPC}.out"
    fi
    nvcc $OPT -arch=sm_80 \
        nfa_gpu_line.o nfa_gpu_chunk_lpc${LPC}.o nfa_cpu_gpu.o \
        utils_gpu.o re2post_gpu.o post2nfa_gpu.o run_benchmark_gpu_chunk.o \
        -o "$BINARY"
    echo "[Build] OK -> $BINARY"

    if [ "$IS_DYNAMIC" -eq 1 ]; then
        LPC_DIR="${OUT_DIR}/lpc_dynamic_${LPC}"
        STRATEGY_DIR="gpu_chunk_dynamic"
        CSV_SUFFIX="_gpu_chunk_dynamic"
    else
        LPC_DIR="${OUT_DIR}/lpc_${LPC}"
        STRATEGY_DIR="gpu_chunk"
        CSV_SUFFIX="_gpu_chunk"
    fi
    mkdir -p "$LPC_DIR"

    # N_RUNS 回 sweep
    for i in $(seq 1 "$N_RUNS"); do
        echo ""
        echo "  --- LPC=$LPC Run $i / $N_RUNS ---"
        RUN_OUT="${LPC_DIR}/run${i}"
        mkdir -p "${RUN_OUT}/${STRATEGY_DIR}"

        # ---- sweep: サイズリストを生成 ----
        MAX_CHARS=$(python3 -c "
with open('$WIKI_FILE', encoding='utf-8', errors='ignore') as f:
    print(len(f.read()))
")
        SIZES=()
        s=100
        while [ "$s" -lt "$MAX_CHARS" ]; do
            SIZES+=("$s")
            s=$((s * 10))
        done
        SIZES+=("$MAX_CHARS")

        MANIFEST="${RUN_OUT}/${STRATEGY_DIR}/manifest.txt"
        > "$MANIFEST"
        mkdir -p "./results"

        for size in "${SIZES[@]}"; do
            echo "    size = ${size} chars"
            ls ./results/results_*${CSV_SUFFIX}.csv 2>/dev/null | sort > /tmp/lpc_before.txt || true
            "$BINARY" "$WIKI_FILE" "$size" || true   # CUDA atexit crash は無視
            ls ./results/results_*${CSV_SUFFIX}.csv 2>/dev/null | sort > /tmp/lpc_after.txt || true
            NEW_FILE=$(comm -13 /tmp/lpc_before.txt /tmp/lpc_after.txt | head -1 || true)

            if [ -z "$NEW_FILE" ]; then
                NEW_FILE=$(ls -t ./results/results_*${CSV_SUFFIX}.csv 2>/dev/null | head -1 || true)
                echo "    [WARN] Fallback to latest: $NEW_FILE"
            fi

            if [ -n "$NEW_FILE" ]; then
                DEST="${RUN_OUT}/${STRATEGY_DIR}/result_size${size}.csv"
                cp "$NEW_FILE" "$DEST"
                echo "    ${DEST}:${size}" >> "$MANIFEST"
            fi
        done

        python3 /app/scripts/aggregate_sweep.py "$MANIFEST" "${RUN_OUT}/${STRATEGY_DIR}/summary.csv"
        echo "  [LPC=$LPC Run$i] Summary -> ${RUN_OUT}/${STRATEGY_DIR}/summary.csv"
    done

    # N_RUNS 回の平均
    SUMMARIES=()
    for i in $(seq 1 "$N_RUNS"); do
        SUMMARIES+=("${LPC_DIR}/run${i}/${STRATEGY_DIR}/summary.csv")
    done
    python3 scripts/average_sweeps.py "${SUMMARIES[@]}" "${LPC_DIR}/avg.csv"
    echo "[LPC=$LPC] Averaged -> ${LPC_DIR}/avg.csv"

done

echo ""
echo "=================================================="
echo " LPC Sweep complete!"
echo " Output : $OUT_DIR"
echo "=================================================="
