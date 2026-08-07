#!/usr/bin/env python3
"""
average_raw_runs.py - raw benchmark CSV (単一サイズ) を N 回分まとめて avg.csv を生成

raw CSV のヘッダ:
  正規表現,検索対象,マッチ行数,マッチ詳細,実行時間(秒),CPU前処理(秒),GPU実行(秒)

avg.csv のヘッダ (average_sweeps.py と同一形式):
  正規表現,文字数,マッチ行数,実行時間(秒),CPU前処理(秒),GPU実行(秒),備考,試行回数

使い方:
  python3 scripts/average_raw_runs.py <size_bytes> run1.csv run2.csv ... output_avg.csv
"""
import csv, sys
from collections import defaultdict

csv.field_size_limit(sys.maxsize)

if len(sys.argv) < 4:
    print("Usage: average_raw_runs.py <file_size_bytes> <run1.csv> [run2.csv ...] <out_avg.csv>")
    sys.exit(1)

file_size_bytes = int(sys.argv[1])
input_files     = sys.argv[2:-1]
output_file     = sys.argv[-1]

times_map    = defaultdict(list)
cpu_pre_map  = defaultdict(list)
gpu_exec_map = defaultdict(list)
match_map    = {}

for fp in input_files:
    with open(fp, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            regex = row["正規表現"].strip().rstrip("\n\r")
            try:
                t = float(row["実行時間(秒)"])
            except (ValueError, KeyError):
                t = 300.0
            cpu_pre  = float(row.get("CPU前処理(秒)", 0) or 0)
            gpu_exec = float(row.get("GPU実行(秒)",   t) or t)
            match_cnt = row.get("マッチ行数", "-")

            key = regex
            times_map[key].append(t)
            cpu_pre_map[key].append(cpu_pre)
            gpu_exec_map[key].append(gpu_exec)
            if key not in match_map:
                match_map[key] = match_cnt

with open(output_file, "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow(["正規表現","文字数","マッチ行数","実行時間(秒)","CPU前処理(秒)","GPU実行(秒)","備考","試行回数"])
    for regex, times in times_map.items():
        n = len(times)
        avg_t   = sum(times) / n
        avg_pre = sum(cpu_pre_map[regex]) / n
        avg_gpu = sum(gpu_exec_map[regex]) / n
        writer.writerow([regex, file_size_bytes, match_map.get(regex, "-"),
                         f"{avg_t:.6f}", f"{avg_pre:.6f}", f"{avg_gpu:.6f}", "", n])

print(f"[Average] {len(times_map)} patterns, {len(input_files)} runs -> {output_file}")
