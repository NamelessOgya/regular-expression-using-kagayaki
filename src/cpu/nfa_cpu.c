/*
 * 正規表現の実装。
 * ( | ) * + ? のみをサポート。エスケープは非対応。
 * NFAにコンパイルし、Thompsonのアルゴリズムを用いてNFAをシミュレートする。
 *
 * 参考: http://swtch.com/~rsc/regexp/ 
 *       Thompson, Ken.  Regular Expression Search Algorithm,
 *       Communications of the ACM 11(6) (June 1968), pp. 419-422.
 * 
 * Copyright (c) 2007 Russ Cox.
 * MITライセンスのもとで配布可能。詳細はファイルの末尾を参照。
 */
 #include <stdio.h>
 #include <stdlib.h>
 #include <string.h>
 #include <unistd.h>
 #include "config.h"
 #include "nfa.h"

 
 

 /*
  * NFAの1つの状態と、そこから出る0個、1個、または2個の矢印（遷移）を表現する。
  * c == Match の場合、外に出る矢印はなく、マッチ状態（終端状態）となる。
  * c == Split の場合、ラベルのない矢印が out と out1 に向かう（out1 が NULL でない場合）。
  * c < 256 の場合、文字 c がラベル付けされた矢印が out に向かう。
  */
 enum
 {
    //通常の文字(0-255の範囲で表現)に加えて3つの文字を定義している。
     Match = 256,
     Split = 257,
     Any   = 258,    /* 追加：ワイルドカード */
 };
 typedef struct State State;
 struct State
 {
     int c;
     State *out; // 次の状態へのポインタ
     State *out1; // Splitの場合のもう一方のポインタ
     int lastlist;
 };
/* マッチ状態: 全フィールドを明示的に初期化 */
// matchstateは、NFAの終端状態を表す。
State matchstate = {
    .c        = Match,
    .out      = NULL,
    .out1     = NULL,
    .lastlist = 0
};

 int nstate;
 
// ステートを増やす関数  
// 
 State*
 state(int c, State *out, State *out1)
 {
     State *s; // ステートのポインタを入れる変数を準備  
     
     nstate++; // ステート数を増やす。
     s = malloc(sizeof *s); // ステート用のメモリを確保

     // ->でポインタの指し示す構造体に代入できる。
     s->lastlist = 0; // 
     s->c = c; // ステートに文字をセット
     s->out = out; // 次の状態へのポインタをセット
     s->out1 = out1; // Splitの場合のもう一方のポインタをセット
     return s; // ステートを返す
 }
 
 /*
  * マッチ状態が設定される前の、部分的に構築されたNFA。
  * Frag.start は開始状態へのポインタ。
  * Frag.out は、このフラグメントの次の状態に設定する必要がある場所（未設定のポインタ）のリスト。
  */
 typedef struct Frag Frag;
 typedef union Ptrlist Ptrlist;
 struct Frag // 断片グラフの入り口と出口を管理する。
 {
     State *start; // NFAの開始状態
     Ptrlist *out; //出口のポインタのリスト Pointer List（ポインタのリスト）
 };
 
 /* Frag構造体を初期化する。 */
 Frag
 frag(State *start, Ptrlist *out)
 {
     Frag n = { start, out };
     return n;
 }
 
 /*
  * リスト内の out ポインタは常に未初期化であるため、
  * それらのポインタ自体を Ptrlist のストレージとして利用する。
  */
 union Ptrlist
 {
     Ptrlist *next;
     State *s;
 };
 
 /* outpのみを含む要素が一つのみのリストを作成する */
 Ptrlist*
 list1(State **outp)
 {
     Ptrlist *l;
     
     l = (Ptrlist*)outp;
     l->next = NULL;
     return l;
 }
 
 /* 状態のリスト out が start を指すようにパッチを当てる（つなぐ）。 */
 void
 patch(Ptrlist *l, State *s)
 {
     Ptrlist *next;
     
     for(; l; l=next){
         next = l->next;
         l->s = s;
     }
 }
 
 /* l1 と l2 の2つのリストを結合し、結合したリストを返す。 */
 Ptrlist*
 append(Ptrlist *l1, Ptrlist *l2)
 {
     Ptrlist *oldl1;
     
     oldl1 = l1;
     while(l1->next)
         l1 = l1->next;
     l1->next = l2;
     return oldl1;
 }
 
/**
 * 後置表現の正規表現文字列から、NFA（非決定性有限オートマトン）のグラフを構成する処理。
 * 
 * [担当処理]
 * `re2post` で作成された後置表現を先頭から順に読み込み、スタックを用いて
 * Thompsonのアルゴリズムに基づいた状態(State)ノード群をメモリ上に確保・連結していきます。
 * 
 * [想定I/O]
 * - input:  後置表現文字列 postfix="ab#"
 * - output: 構築されたNFAの先頭状態 (State *) へのポインタ
 */
 State
 *post2nfa(char *postfix)
 {
     char *p;
     Frag stack[1000], *stackp, e1, e2, e;
     State *s;
     
     // fprintf(stderr, "postfix: %s\n", postfix);
 
     if(postfix == NULL)
         return NULL;
 
     #define push(s) *stackp++ = s
     #define pop() *--stackp
 
     stackp = stack;
     for(p=postfix; *p; p++){
         switch(*p){
         case '.':  /* ワイルドカード */
             /* Any 状態を作り出して list1(&s->out) */
             s = state(Any, NULL, NULL);
             push(frag(s, list1(&s->out)));
             break;
         case '#':	/* 結合 (catenate) */
             e2 = pop();
             e1 = pop();
             patch(e1.out, e2.start);
             push(frag(e1.start, e2.out));
             break;
         case '|':	/* 選択 (alternate) */
             e2 = pop();
             e1 = pop();
             s = state(Split, e1.start, e2.start);
             push(frag(s, append(e1.out, e2.out)));
             break;
         case '?':	/* 0回または1回 (zero or one) */
             e = pop();
             s = state(Split, e.start, NULL);
             push(frag(s, append(e.out, list1(&s->out1))));
             break;
         case '*':	/* 0回以上の繰り返し (zero or more) */
             e = pop();
             s = state(Split, e.start, NULL);
             patch(e.out, s);
             push(frag(s, list1(&s->out1)));
             break;
         case '+':	/* 1回以上の繰り返し (one or more) */
             e = pop();
             s = state(Split, e.start, NULL);
             patch(e.out, s);
             push(frag(e.start, list1(&s->out1)));
             break;
         default:
             s = state((unsigned char)*p, NULL, NULL);
             push(frag(s, list1(&s->out)));
             break;
         }
     }
 
     e = pop();
     if(stackp != stack)
         return NULL;
 
     patch(e.out, &matchstate);
     return e.start;
 #undef pop
 #undef push
 }
 
 typedef struct List List;
 struct List
 {
     State **s;
     int n;
 };
 List l1, l2;
 static int listid;
 
 void addstate(List*, State*);
 void step(List*, int, List*);
 
 /* 初期状態のリストを計算する */
 List*
 startlist(State *start, List *l)
 {
     l->n = 0;
     listid++;
     addstate(l, start);
     return l;
 }
 
 /* 状態リストにマッチ状態が含まれているかを確認する。 */
 int
 ismatch(List *l)
 {
     int i;
 
     for(i=0; i<l->n; i++)
         if(l->s[i] == &matchstate)
             return 1;
     return 0;
 }
 
 /* ラベルのない矢印（Splitなど）をたどりながら、状態 s をリスト l に追加する。 */
 void
 addstate(List *l, State *s)
 {
     if(s == NULL || s->lastlist == listid)
         return;
     s->lastlist = listid;
     if(s->c == Split){
         /* ラベルのない矢印をたどる */
         addstate(l, s->out);
         addstate(l, s->out1);
         return;
     }
     l->s[l->n++] = s;
 }
 
 /*
  * 現在の状態リスト clist から文字 c の遷移を1ステップ進め、
  * 次のNFA状態の集合 nlist を作成する。
  */
 void
 step(List *clist, int c, List *nlist)
 {
     int i;
     State *s;
 
     listid++;
     nlist->n = 0;
     for(i=0; i<clist->n; i++){
         s = clist->s[i];
         if(s->c == c || s->c == Any)   /* Any はどんな文字ともマッチ */
             addstate(nlist, s->out);
     }
 }
 
 /* NFAを実行し、文字列 s にマッチするか判定する。 */
 int
 match(State *start, char *s)
 {
     int c;
     List *clist, *nlist, *t;
 
     clist = startlist(start, &l1);
     nlist = &l2;
     for(; *s; s++){
         c = *s & 0xFF;
         step(clist, c, nlist);
         t = clist; clist = nlist; nlist = t;	/* clist と nlist を交換 */
     }
     
     return ismatch(clist);
 }

/* --- 追加: NFA ラッパ構造体 ------------------- */
struct NFA {
    State  *start;   /* 受理オートマトン先頭 */
    State **state_pool; /* malloc した State* 配列 (free用) */
    size_t  nstate;
    List    l1, l2;  /* 再利用するリスト領域 */
};

/**
 * NFAを用いて、入力文字列がパターンの「最初から最後まで完全に一致」するか判定する処理。
 * 
 * [担当処理]
 * 構築されたNFAを先頭状態からスタートし、渡された文字列(`text`)を1文字ずつ消費させながら
 * 全ての状態遷移をシミュレーションします。文字列を最後まで読み切った時点でMatch状態に
 * 到達していれば真を返します。
 * 
 * [想定I/O]
 * - input:  コンパイル済みNFA構造体 nfa, 検索対象テキスト text
 * - output: 完全にマッチすれば 1 (True)、しなければ 0 (False)
 */
int nfa_test(const NFA *nfa, const char *text)
{
    /* NFA が持つ２つの List 領域を参照 */
    List *clist = startlist(nfa->start, &nfa->l1);
    List *nlist = &nfa->l2;

    /* 各文字についてループ */
    for (const unsigned char *p = (const unsigned char*)text; *p; ++p) {
        /* 今の状態集合 clist から文字 *p を遷移して nlist へ */
        step(clist, *p, nlist);
        /* clist と nlist をスワップ */
        List *tmp = clist;
        clist = nlist;
        nlist = tmp;
    }
    /* 最後の状態集合に Match があれば 1、なければ 0 */
    return ismatch(clist);
}

/**
 * 正規表現からNFA（実行用構造体）を生成・メモリ確保するメインAPI。
 * 
 * [担当処理]
 * ユーザーが指定した正規表現文字列を受け取り、内部で `re2post` と `post2nfa` を呼び出して
 * 状態遷移グラフを作成します。生成したグラフや後で使うメモリ領域を `NFA` 構造体に
 * 格納して返却します。
 * 
 * [想定I/O]
 * - input:  正規表現文字列 regex="a(b|c)*"
 * - output: 動的確保された NFA構造体 へのポインタ（利用後は nfa_free が必要）
 */
NFA *nfa_compile(const char *regex)
{
    char  *post = re2post((char *)regex);
    if (!post) return NULL;

    State *start = post2nfa(post);
    if (!start)  return NULL;

    /* プール確保 (nstate は post2nfa 内の global) */
    NFA *nfa = malloc(sizeof *nfa);
    nfa->start = start;
    nfa->nstate = nstate;
    nfa->state_pool = malloc(nstate * sizeof(State *));
    /* 生成された State を DFS で収集して pool に詰める …省略(※) */

    /* List 配列もここで確保 */
    nfa->l1.s = malloc(nstate * sizeof(State *));
    nfa->l2.s = malloc(nstate * sizeof(State *));
    return nfa;
}

/**
 * 長大なテキストの中から、正規表現に部分一致（Substring Match）する箇所が存在するか探索するAPI。
 * 
 * [担当処理]
 * テキストの先頭（0文字目）から順にマッチングを試み、失敗したら1文字ずらして再試行します。
 * NFAがMatch状態に到達した瞬間に探索対象を発見したとみなし、即座に終了して真を返します。
 * 
 * [想定I/O]
 * - input:  コンパイル済みNFA構造体 nfa, 巨大な検索対象テキスト text
 * - output: パターンが見つかれば 1 (True)、全く見つからなければ 0 (False)
 */
int nfa_search(const NFA *nfa, const char *text)
{
    if (!nfa || !text) return 0;

    /* const を外す (既存の実装の流儀に従う) */
    List *l1_ptr = (List*)&nfa->l1;
    List *l2_ptr = (List*)&nfa->l2;

    /* すべての文字の開始位置からマッチングを試みる */
    for (int i = 0; text[i] != '\0'; ++i) {
        List *clist = startlist(nfa->start, l1_ptr);
        List *nlist = l2_ptr;

        /* 空文字で即マッチ可能（^など）なケースへの対応 */
        if (ismatch(clist)) {
            return 1;
        }

        for (const unsigned char *p = (const unsigned char*)(text + i); *p; ++p) {
            step(clist, *p, nlist);
            List *tmp = clist;
            clist = nlist;
            nlist = tmp;

            /* 途中でマッチ状態に到達したらそこで探索成功として返す */
            if (ismatch(clist)) {
                return 1;
            }
            /* 可能性が完全に途絶えたら内部ループを早抜け */
            if (clist->n == 0) {
                break;
            }
        }
    }
    return 0;
}

/**
 * nfa_compile で確保された NFA 構造体や内部状態ノードを一括で破棄する処理。
 * 
 * [担当処理]
 * NFA内に紐づくプールされたState群、やリスト領域、NFA本体を `free` して
 * メモリリークを防止します。
 * 
 * [想定I/O]
 * - input:  破棄対象のNFA構造体 nfa
 * - output: なし
 */
void nfa_free(NFA *nfa)
{
    if (!nfa) return;
    for (size_t i = 0; i < nfa->nstate; ++i)
        free(nfa->state_pool[i]);
    free(nfa->state_pool);
    free(nfa->l1.s);
    free(nfa->l2.s);
    free(nfa);
}
 
 /*
  * 【MITライセンス 日本語訳】
  * 以下に定める条件に従い、本ソフトウェアおよび関連文書のファイル（以下「ソフトウェア」）の複製を
  * 取得するすべての人に対し、ソフトウェアを無制限に扱うことを無償で許可します。
  * これには、ソフトウェアの複製を使用、複写、変更、結合、掲載、頒布、サブライセンス、
  * および/または販売する権利、およびソフトウェアを提供する相手に同じことを許可する権利も含まれます。
  * 
  * 上記の著作権表示および本許諾表示を、ソフトウェアのすべての複製または重要な部分に記載するものとします。
  * 
  * ソフトウェアは「現状のまま」提供され、明示であるか暗黙であるかを問わず、何らの保証もありません。
  * ここでいう保証とは、商品性、特定の目的への適合性、および権利非侵害についての保証も含みますが、
  * それに限定されるものではありません。作者または著作権者は、契約行為、不法行為、またはそれ以外であろうと、
  * ソフトウェアに起因または関連し、あるいはソフトウェアの使用またはその他の扱いによって生じる
  * 一切の請求、損害、その他の義務について何らの責任も負わないものとします。
  */