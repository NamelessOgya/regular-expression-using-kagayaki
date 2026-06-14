#!/usr/bin/env python3
"""
average_sweeps.py - 複数回のスイープsummary.csvを平均してひとつのCSVにまとめる

使い方:
  python3 scripts/average_sweeps.py run1/summary.csv run2/summary.csv run3/summary.csv output_avg.csv
"""
import csv
import sys
from collections import defaultdict

csv.field_size_limit(sys.maxsize)

if len(sys.argv) < 3:
    print("Usage: average_sweeps.py <input1.csv> [input2.csv ...] <output.csv>")
    sys.exit(1)

input_files = sys.argv[1:-1]
output_file = sys.argv[-1]

# (regex, size) -> list of execution times, pre times, and exec times
times_map = defaultdict(list)
cpu_pre_map = defaultdict(list)
gpu_exec_map = defaultdict(list)
match_count_map = {}   # 1回目の値を代表値として使用

for filepath in input_files:
    with open(filepath, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            regex = row["正規表現"].strip().rstrip("\n\r")
            size  = int(row["文字数"])
            note  = row.get("備考", "").strip()
            try:
                t = float(row["実行時間(秒)"])
            except ValueError:
                t = 300.0
            if note == "TIMEOUT":
                t = 300.0
            
            cpu_pre_str = row.get("CPU前処理(秒)")
            gpu_exec_str = row.get("GPU実行(秒)")
            
            try:
                cpu_pre = float(cpu_pre_str) if cpu_pre_str is not None else 0.0
            except ValueError:
                cpu_pre = 0.0
                
            try:
                gpu_exec = float(gpu_exec_str) if gpu_exec_str is not None else t
            except ValueError:
                gpu_exec = t
                
            if note == "TIMEOUT":
                cpu_pre = 0.0
                gpu_exec = 300.0
                
            key = (regex, size)
            times_map[key].append(t)
            cpu_pre_map[key].append(cpu_pre)
            gpu_exec_map[key].append(gpu_exec)
            if key not in match_count_map:
                match_count_map[key] = row.get("マッチ行数", "-")

# 出力: 正規表現 / 文字数 でソートして書き出す
rows = []
for (regex, size), times in times_map.items():
    n = len(times)
    avg_time = sum(times) / n
    avg_cpu_pre = sum(cpu_pre_map[(regex, size)]) / n
    avg_gpu_exec = sum(gpu_exec_map[(regex, size)]) / n
    n_timeout = sum(1 for t in times if t >= 300.0)

    if n_timeout == n:
        note = "TIMEOUT"
    elif n_timeout > 0:
        note = f"TIMEOUT({n_timeout}/{n})"
    else:
        note = ""

    rows.append((regex, size, match_count_map.get((regex, size), "-"),
                 avg_time, avg_cpu_pre, avg_gpu_exec, note, n))

# 正規表現の出現順を保持するためファイル順でソート
rows.sort(key=lambda r: r[1])   # まずサイズでソート

with open(output_file, "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow(["正規表現", "文字数", "マッチ行数", "実行時間(秒)", "CPU前処理(秒)", "GPU実行(秒)", "備考", "試行回数"])
    for regex, size, count, avg_time, avg_cpu_pre, avg_gpu_exec, note, n in rows:
        writer.writerow([regex, size, count, f"{avg_time:.6f}", f"{avg_cpu_pre:.6f}", f"{avg_gpu_exec:.6f}", note, n])

print(f"[Average] {len(rows)} entries from {len(input_files)} runs -> {output_file}")
