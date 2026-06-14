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

# (regex, size) -> list of execution times
times_map: dict = defaultdict(list)
match_count_map: dict = {}   # 1回目の値を代表値として使用

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
            key = (regex, size)
            times_map[key].append(t)
            if key not in match_count_map:
                match_count_map[key] = row.get("マッチ行数", "-")

# 出力: 正規表現 / 文字数 でソートして書き出す
rows = []
for (regex, size), times in times_map.items():
    n = len(times)
    avg_time = sum(times) / n
    n_timeout = sum(1 for t in times if t >= 300.0)

    if n_timeout == n:
        note = "TIMEOUT"
    elif n_timeout > 0:
        note = f"TIMEOUT({n_timeout}/{n})"
    else:
        note = ""

    rows.append((regex, size, match_count_map.get((regex, size), "-"),
                 avg_time, note, n))

# 正規表現の出現順を保持するためファイル順でソート
rows.sort(key=lambda r: r[1])   # まずサイズでソート

with open(output_file, "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow(["正規表現", "文字数", "マッチ行数", "実行時間(秒)", "備考", "試行回数"])
    for regex, size, count, avg_time, note, n in rows:
        writer.writerow([regex, size, count, f"{avg_time:.6f}", note, n])

print(f"[Average] {len(rows)} entries from {len(input_files)} runs -> {output_file}")
