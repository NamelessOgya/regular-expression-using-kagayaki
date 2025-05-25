#!/usr/bin/env bash
set -e

INC="-I./include"
# デバッグ＋ASan 用フラグ
CFLAGS="-g -O1 -fsanitize=address -fno-omit-frame-pointer -Wall -Wextra"
LDFLAGS="-fsanitize=address"

# 1) ライブラリ部をオブジェクト化
gcc $INC $CFLAGS -c sandbox/nfa.c -o nfa.o

# 2) テストプログラムをオブジェクト化
gcc $INC $CFLAGS -c src/test_nfa.c -o test_nfa.o

# 3) リンクして実行ファイル生成
gcc $LDFLAGS nfa.o test_nfa.o -o test_nfa.asan

# 4) 実行
chmod +x test_nfa.asan
./test_nfa.asan
