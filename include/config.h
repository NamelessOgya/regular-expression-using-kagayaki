/* config.h */
#pragma once

#define MAX_LINE_LENGTH 10000//最大の1文の文字数
#define MAX_SENTENCE_LENGTH 100000 //最大のsentence数
#define MAX_RESULT_LENGTH 10000 //最大のresult文字列の長さ
#define NUM_COL 2
#define OUTPUT_CSV_TEMPLATE "./results/results_%s%s.csv"   /* ← %s を 2 つに */
#define NFA_EXECUTABLE "./nfa.out"