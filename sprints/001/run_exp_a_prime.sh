#!/usr/bin/env bash
# =============================================================
# sprints/001/run_exp_a_prime.sh
#
# 実験 A': enwik8 での LPC スイープ（LPC=1,2,4,8）× 3回平均
#
# 目的:
#   LPC を小さくするほど Chunked-Static/Dynamic の GPU 実行時間が
#   短くなるという仮説を検証する。
#   - LPC=1 → Static ≈ GPU Line（1スレッド = 1行、直列処理なし）
#   - LPC=8 → 実験 A の計測済み値（比較用）
#
# 使い方（リポジトリルートから実行）:
#   bash sprints/001/run_exp_a_prime.sh
#
# 出力:
#   results/sprint001_exp_a_prime/
#     lpc_1/        avg.csv   (Chunked-Static, LPC=1)
#     lpc_2/        avg.csv
#     lpc_4/        avg.csv
#     lpc_8/        avg.csv
#     lpc_dynamic_1/ avg.csv  (Chunked-Dynamic, LPC=1)
#     lpc_dynamic_2/ avg.csv
#     lpc_dynamic_4/ avg.csv
#     lpc_dynamic_8/ avg.csv
#
# 注意: Static LPC=1,2,4,8 の .out バイナリは既存のものを再利用する。
#       Dynamic バイナリのみコンパイルが必要（初回 ~3 分）。
# =============================================================
set -e

# このスクリプトは Docker コンテナ内で実行してください:
#   docker run --rm --gpus all -v "$(pwd)":/app re_exp_env_gpu bash -c \
#     "cd /app && bash sprints/001/run_exp_a_prime.sh"

WIKI_FILE="./data/wiki_plain.txt"
OUT_DIR="./results/sprint001_exp_a_prime"
N_RUNS=3
LPC_VALUES=(1 2 4 8 16 32)

echo "=============================================="
echo " 実験 A': enwik8 × LPC スイープ（仮説検証）"
echo " データ  : $WIKI_FILE"
echo " 出力先  : $OUT_DIR"
echo " LPC 値  : ${LPC_VALUES[*]}"
echo " 繰り返し: ${N_RUNS} 回平均"
echo "=============================================="
mkdir -p "$OUT_DIR"

# ----------------------------------------------------------
# enwik8 の全文字数を取得
# ----------------------------------------------------------
MAX_CHARS=$(wc -c < "$WIKI_FILE")
echo "enwik8 サイズ: ${MAX_CHARS} bytes"
echo ""

# ----------------------------------------------------------
# sweep 実行の共通関数
# ----------------------------------------------------------
run_sweep_and_average() {
    local binary="$1"
    local strategy_dir="$2"     # gpu_chunk or gpu_chunk_dynamic
    local csv_suffix="$3"       # _gpu_chunk or _gpu_chunk_dynamic
    local lpc_dir="$4"          # 出力ディレクトリ
    local lpc="$5"

    mkdir -p "$lpc_dir"
    local summaries=()

    for i in $(seq 1 "$N_RUNS"); do
        echo "  --- LPC=$lpc Run $i / $N_RUNS ---"
        local run_out="${lpc_dir}/run${i}/${strategy_dir}"
        mkdir -p "$run_out"

        # サイズ一覧（100, 1000, ..., MAX_CHARS）
        local sizes=()
        local s=100
        while [ "$s" -lt "$MAX_CHARS" ]; do
            sizes+=("$s")
            s=$((s * 10))
        done
        sizes+=("$MAX_CHARS")

        local manifest="${run_out}/manifest.txt"
        > "$manifest"
        mkdir -p "./results"

        for size in "${sizes[@]}"; do
            echo "    size = ${size} chars"
            ls ./results/results_*${csv_suffix}.csv 2>/dev/null | sort > /tmp/exp_a_before.txt || true
            "$binary" "$WIKI_FILE" "$size" || true
            ls ./results/results_*${csv_suffix}.csv 2>/dev/null | sort > /tmp/exp_a_after.txt || true
            local new_file
            new_file=$(comm -13 /tmp/exp_a_before.txt /tmp/exp_a_after.txt | head -1 || true)
            if [ -z "$new_file" ]; then
                new_file=$(ls -t ./results/results_*${csv_suffix}.csv 2>/dev/null | head -1 || true)
            fi
            if [ -n "$new_file" ]; then
                local dest="${run_out}/result_size${size}.csv"
                cp "$new_file" "$dest"
                echo "    ${dest}:${size}" >> "$manifest"
            fi
        done

        python3 scripts/aggregate_sweep.py "$manifest" "${run_out}/summary.csv"
        echo "  [LPC=$lpc Run$i] → ${run_out}/summary.csv"
        summaries+=("${run_out}/summary.csv")
    done

    python3 scripts/average_sweeps.py "${summaries[@]}" "${lpc_dir}/avg.csv"
    echo "[LPC=$lpc] 平均 → ${lpc_dir}/avg.csv"
}

# ----------------------------------------------------------
# 1. Chunked-Static: 既存バイナリを再利用
# ----------------------------------------------------------
echo ">>> [1/2] Chunked-Static LPC スイープ（既存バイナリを再利用）"
for lpc in "${LPC_VALUES[@]}"; do
    BINARY="./run_benchmark_gpu_chunk_lpc${lpc}.out"
    if [ ! -f "$BINARY" ]; then
        echo "[ERROR] バイナリが見つかりません: $BINARY"
        echo "  → run_lpc_sweep.sh を先に実行してください"
        exit 1
    fi
    echo ""
    echo "=== Static LPC=$lpc ==="
    run_sweep_and_average \
        "$BINARY" \
        "gpu_chunk" \
        "_gpu_chunk" \
        "${OUT_DIR}/lpc_${lpc}" \
        "$lpc"
done

# ----------------------------------------------------------
# 2. Chunked-Dynamic: バイナリをコンパイルして実行
# ----------------------------------------------------------
echo ""
echo ">>> [2/2] Chunked-Dynamic LPC スイープ（コンパイル + 実行）"

INC="-I./include -I./src/gpu -I./src/gpu/common -I./src/gpu/line_parallel -I./src/gpu/chunk_parallel"
OPT="-O3"

# 共有オブジェクトのビルド（Dynamic 用）
echo "[Build] Shared objects for Dynamic..."
nvcc $OPT -arch=sm_80 $INC -c src/gpu/line_parallel/nfa_gpu_line.cu  -o nfa_gpu_line.o
gcc  $OPT -DGPU_CHUNK_DYNAMIC_RUN $INC -c src/cpu/nfa_cpu.c           -o nfa_cpu_gpu.o
gcc  $OPT -DGPU_CHUNK_DYNAMIC_RUN $INC -c src/common/utils.c          -o utils_gpu.o
gcc  $OPT -DGPU_CHUNK_DYNAMIC_RUN $INC -c src/common/re2post.c        -o re2post_gpu.o
gcc  $OPT -DGPU_CHUNK_DYNAMIC_RUN $INC -c src/common/post2nfa.c       -o post2nfa_gpu.o
gcc  $OPT -DGPU_CHUNK_DYNAMIC_RUN $INC -c app/run_benchmark.c         -o run_benchmark_gpu_chunk.o

for lpc in "${LPC_VALUES[@]}"; do
    echo ""
    echo "=== Dynamic LPC=$lpc ==="
    echo "[Build] nfa_gpu_chunk_dynamic_lpc${lpc}..."
    nvcc $OPT -arch=sm_80 $INC \
        -DLINES_PER_CHUNK=${lpc} \
        -DGPU_CHUNK_DYNAMIC_RUN \
        -c src/gpu/chunk_parallel/nfa_gpu_chunk.cu \
        -o nfa_gpu_chunk_dyn_lpc${lpc}.o

    BINARY="./run_benchmark_gpu_chunk_dynamic_lpc${lpc}.out"
    nvcc $OPT -arch=sm_80 \
        nfa_gpu_line.o nfa_gpu_chunk_dyn_lpc${lpc}.o nfa_cpu_gpu.o \
        utils_gpu.o re2post_gpu.o post2nfa_gpu.o run_benchmark_gpu_chunk.o \
        -o "$BINARY"
    echo "[Build] OK → $BINARY"

    run_sweep_and_average \
        "$BINARY" \
        "gpu_chunk_dynamic" \
        "_gpu_chunk_dynamic" \
        "${OUT_DIR}/lpc_dynamic_${lpc}" \
        "$lpc"
done

echo ""
echo "=============================================="
echo " 実験 A' 完了!"
echo " 結果ディレクトリ: $OUT_DIR"
echo " 次のステップ: python3 sprints/001/analyze_exp_a_prime.py"
echo "=============================================="
