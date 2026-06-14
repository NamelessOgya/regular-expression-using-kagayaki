#!/usr/bin/env bash
# =============================================================
# run_all.sh
# CPU + GPU(Line) + GPU(Chunk) + LPC Sweep を N 回ずつ実行し、平均してグラフを生成する。
#
# 出力構造:
#   results/
#     run_<timestamp>/
#       cpu/
#         run1/  run2/  run3/
#         avg.csv
#       gpu_line/
#         run1/gpu_line/  run2/gpu_line/  run3/gpu_line/
#         avg.csv
#       gpu_chunk/
#         run1/gpu_chunk/  run2/gpu_chunk/  run3/gpu_chunk/
#         avg.csv
#       plots/
#         benchmark_grid.png
#     latest -> run_<timestamp>
#
# 使い方:
#   ./run_all.sh                  # CPU + GPU×2 + LPC sweep, 3回ずつ
#   ./run_all.sh --cpu-only       # CPU のみ
#   ./run_all.sh --runs 5         # 5回ずつ
#   ./run_all.sh --skip-lpc       # LPC sweep をスキップ
# =============================================================
set -e

# --------------------------------------------------------
# 引数の解析
# --------------------------------------------------------
CPU_ONLY=0
SKIP_LPC=1
N_RUNS=3
WIKI_FILE="./data/wiki_plain.txt"
# LPC sweep 値: 1=Line-Parallel相当, 8=現在のデフォルト, その先も比較
LPC_VALUES=(1 2 4 8 16 32)

while [[ $# -gt 0 ]]; do
    case $1 in
        --cpu-only) CPU_ONLY=1; shift ;;
        --skip-lpc) SKIP_LPC=1; shift ;;
        --runs)     N_RUNS="$2"; shift 2 ;;
        *)          WIKI_FILE="$1"; shift ;;
    esac
done

if [ ! -f "$WIKI_FILE" ]; then
    echo "[ERROR] Target file not found: $WIKI_FILE"
    exit 1
fi

TIMESTAMP=$(date +%Y%m%d_%H_%M_%S)
RUN_DIR="./results/run_${TIMESTAMP}"
mkdir -p "$RUN_DIR/cpu" "$RUN_DIR/gpu_line" "$RUN_DIR/gpu_chunk" "$RUN_DIR/gpu_chunk_dynamic" "$RUN_DIR/plots" "$RUN_DIR/lpc_sweep"

echo "=========================================="
echo " run_all.sh"
echo " Run dir  : $RUN_DIR"
echo " Repeats  : $N_RUNS"
echo " $(date '+%Y-%m-%d %H:%M:%S')"
echo "=========================================="

# --------------------------------------------------------
# 1. CPU スイープ (N回)
# --------------------------------------------------------
echo ""
echo ">>> [1/5] CPU Sweeps (x${N_RUNS})"

for i in $(seq 1 "$N_RUNS"); do
    echo ""
    echo "  --- CPU Run $i / $N_RUNS ---"
    bash run_sweep.sh "$WIKI_FILE" --out "$RUN_DIR/cpu/run${i}"
done

echo ""
echo "  --- CPU: Averaging ${N_RUNS} runs ---"
CPU_SUMMARIES=()
for i in $(seq 1 "$N_RUNS"); do
    CPU_SUMMARIES+=("$RUN_DIR/cpu/run${i}/summary.csv")
done
python3 scripts/average_sweeps.py "${CPU_SUMMARIES[@]}" "$RUN_DIR/cpu/avg.csv"

# --------------------------------------------------------
# 2. GPU スイープ (N回) - run_sweep_gpu.sh が Line + Chunk 両方を実行
# --------------------------------------------------------
if [ "$CPU_ONLY" -eq 0 ]; then
    echo ""
    echo ">>> [2/5] GPU Sweeps (Line-Parallel + Chunk-Parallel + Dynamic, x${N_RUNS})"

    for i in $(seq 1 "$N_RUNS"); do
        echo ""
        echo "  --- GPU Run $i / $N_RUNS ---"
        # run_sweep_gpu.sh は OUT_DIR/gpu_line/, OUT_DIR/gpu_chunk/, OUT_DIR/gpu_chunk_dynamic/ に出力する
        bash run_sweep_gpu.sh "$WIKI_FILE" --out "$RUN_DIR/gpu/run${i}"
    done

    # GPU Line の平均
    echo ""
    echo "  --- GPU Line: Averaging ${N_RUNS} runs ---"
    GPU_LINE_SUMMARIES=()
    for i in $(seq 1 "$N_RUNS"); do
        GPU_LINE_SUMMARIES+=("$RUN_DIR/gpu/run${i}/gpu_line/summary.csv")
    done
    python3 scripts/average_sweeps.py "${GPU_LINE_SUMMARIES[@]}" "$RUN_DIR/gpu_line/avg.csv"

    # GPU Chunk の平均
    echo ""
    echo "  --- GPU Chunk: Averaging ${N_RUNS} runs ---"
    GPU_CHUNK_SUMMARIES=()
    for i in $(seq 1 "$N_RUNS"); do
        GPU_CHUNK_SUMMARIES+=("$RUN_DIR/gpu/run${i}/gpu_chunk/summary.csv")
    done
    python3 scripts/average_sweeps.py "${GPU_CHUNK_SUMMARIES[@]}" "$RUN_DIR/gpu_chunk/avg.csv"

    # GPU Chunk Dynamic の平均
    echo ""
    echo "  --- GPU Chunk Dynamic: Averaging ${N_RUNS} runs ---"
    GPU_CHUNK_DYN_SUMMARIES=()
    for i in $(seq 1 "$N_RUNS"); do
        GPU_CHUNK_DYN_SUMMARIES+=("$RUN_DIR/gpu/run${i}/gpu_chunk_dynamic/summary.csv")
    done
    python3 scripts/average_sweeps.py "${GPU_CHUNK_DYN_SUMMARIES[@]}" "$RUN_DIR/gpu_chunk_dynamic/avg.csv"

else
    echo ""
    echo ">>> [2/5] GPU Sweeps: SKIPPED (--cpu-only)"
fi

# --------------------------------------------------------
# 3. LINES_PER_CHUNK スイープ
# --------------------------------------------------------
if [ "$CPU_ONLY" -eq 0 ] && [ "$SKIP_LPC" -eq 0 ]; then
    echo ""
    echo ">>> [3/5] LINES_PER_CHUNK Sweep (N=${LPC_VALUES[*]}, x${N_RUNS} runs each)"

    LPC_ARGS=""
    for lpc in "${LPC_VALUES[@]}"; do
        LPC_ARGS="$LPC_ARGS $lpc"
    done

    echo "--- Running Static LPC Sweep ---"
    bash run_lpc_sweep.sh "$WIKI_FILE" \
        --out "$RUN_DIR/lpc_sweep" \
        --runs "$N_RUNS" \
        --lpc $LPC_ARGS

    echo "--- Running Dynamic LPC Sweep ---"
    bash run_lpc_sweep.sh "$WIKI_FILE" \
        --out "$RUN_DIR/lpc_sweep" \
        --runs "$N_RUNS" \
        --dynamic \
        --lpc $LPC_ARGS
else
    echo ""
    echo ">>> [3/5] LPC Sweep: SKIPPED"
fi

# --------------------------------------------------------
# 4. グラフ生成 (CPU vs GPU)
# --------------------------------------------------------
echo ""
echo ">>> [4/5] Plotting (CPU vs GPU)"

PLOT_ARGS="--cpu $RUN_DIR/cpu/avg.csv --out $RUN_DIR/plots"
if [ "$CPU_ONLY" -eq 0 ]; then
    if [ -f "$RUN_DIR/gpu_line/avg.csv" ]; then
        PLOT_ARGS="$PLOT_ARGS --gpu-line $RUN_DIR/gpu_line/avg.csv"
    fi
    if [ -f "$RUN_DIR/gpu_chunk/avg.csv" ]; then
        PLOT_ARGS="$PLOT_ARGS --gpu-chunk $RUN_DIR/gpu_chunk/avg.csv"
    fi
    if [ -f "$RUN_DIR/gpu_chunk_dynamic/avg.csv" ]; then
        PLOT_ARGS="$PLOT_ARGS --gpu-chunk-dynamic $RUN_DIR/gpu_chunk_dynamic/avg.csv"
    fi
fi

python3 scripts/plot_benchmark.py $PLOT_ARGS

# --------------------------------------------------------
# 5. LPC sweep グラフ生成
# --------------------------------------------------------
if [ "$CPU_ONLY" -eq 0 ] && [ "$SKIP_LPC" -eq 0 ]; then
    echo ""
    echo ">>> [5/5] Plotting (LPC Sweep)"

    LPC_PLOT_ARGS="--out $RUN_DIR/plots"
    if [ -f "$RUN_DIR/cpu/avg.csv" ]; then
        LPC_PLOT_ARGS="$LPC_PLOT_ARGS --cpu $RUN_DIR/cpu/avg.csv"
    fi
    if [ "$RUN_DIR/gpu_line/avg.csv" ]; then
        LPC_PLOT_ARGS="$LPC_PLOT_ARGS --gpu-line $RUN_DIR/gpu_line/avg.csv"
    fi
    for lpc in "${LPC_VALUES[@]}"; do
        AVG="$RUN_DIR/lpc_sweep/lpc_${lpc}/avg.csv"
        if [ -f "$AVG" ]; then
            LPC_PLOT_ARGS="$LPC_PLOT_ARGS --lpc ${lpc}:${AVG}"
        fi
        AVG_DYN="$RUN_DIR/lpc_sweep/lpc_dynamic_${lpc}/avg.csv"
        if [ -f "$AVG_DYN" ]; then
            LPC_PLOT_ARGS="$LPC_PLOT_ARGS --lpc-dynamic ${lpc}:${AVG_DYN}"
        fi
    done

    python3 scripts/plot_lpc_sweep.py $LPC_PLOT_ARGS
else
    echo ""
    echo ">>> [5/5] LPC Plot: SKIPPED"
fi

# --------------------------------------------------------
# latest シンボリックリンクを更新
# --------------------------------------------------------
ln -sfn "run_${TIMESTAMP}" ./results/latest
echo ""
echo "=========================================="
echo " All done!"
echo "  Run dir   : $RUN_DIR"
echo "  Latest    : results/latest -> run_${TIMESTAMP}"
echo "  Grid plot : $RUN_DIR/plots/benchmark_grid.png"
echo "  LPC plot  : $RUN_DIR/plots/lpc_sweep_grid.png"
echo "=========================================="
