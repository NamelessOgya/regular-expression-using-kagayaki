/* config.h */
#pragma once

#define MAX_LINE_LENGTH 2048
#define MAX_SENTENCE_LENGTH 2048
#define MAX_NUM_LINE 100
#define NUM_COL 2
#define MAX_COMMAND_LENGTH 1024
// #define OUTPUT_CSV_TEMPLATE "./results/results_%s.csv"
#define OUTPUT_CSV_TEMPLATE "./results/results_%s%s.csv"   /* ← %s を 2 つに */
#define NFA_EXECUTABLE "./nfa.out"