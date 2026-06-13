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

/**
 * NFAの探索時に、シミュレーションの「分身たち」が現在どこの部屋にいるかを記憶するためのリスト。
 * NFAは同時に複数の異なる部屋に存在できるため、現在の状態群を配列で一括管理します。
 */
 List l1, l2;
 static int listid;
 
 void addstate(List*, State*);
 void step(List*, int, List*);
 
/**
 * 探索の開始地点（初期リスト）をセットアップする関数。
 * 開始状態から文字を消費せずに進める範囲（ε遷移）をすべて洗い出し、リスト l に登録します。
 */
 List*
 startlist(State *start, List *l)
 {
     l->n = 0;
     listid++;
     addstate(l, start);
     return l;
 }
 
/**
 * 現在のリスト（分身たちの居場所）の中に、ゴールである Match 状態に
 * 到達している分身が存在するかを確認する関数。
 */
 int
 ismatch(List *l)
 {
     int i;
 
     for(i=0; i<l->n; i++)
         if(l->s[i] == &matchstate)
             return 1;
     return 0;
 }
 
/**
 * 探索の「分身」を特定の部屋（State）に配置する関数。
 *
 * [担当処理]
 * 単にリストへ部屋を登録するだけでなく、「文字を消費せずに通り抜けられる
 * ラベルのない矢印（Splitなど）」にぶつかった場合は、その矢印を再帰的に
 * 根こそぎ辿って、行ける範囲すべての部屋に分身をばらまきます。
 * また、lastlist を使って同じステップでの重複探索や無限ループを防ぎます。
 */
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
 
/**
 * NFAの「分身たち」を一斉に次の部屋へ進める（1ステップ進める）処理。
 *
 * [担当処理]
 * 現在の部屋リスト (clist) にいるすべての分身について、
 * 引数で与えられた1文字 (c) を消費して進める道があるか確認します。
 * 道があれば、その先の部屋を次のリスト (nlist) に配置（addstate）します。
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
 
/**
 * （旧）NFAを実行し、文字列 s に完全にマッチするか判定する。
 * 現在は nfa_test などのラッパーAPI経由で利用されることの多い、基盤となる実行用関数です。
 */
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

/* struct NFA is now defined in include/nfa.h */

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
    List *clist = startlist(nfa->start, (List*)&nfa->l1);
    List *nlist = (List*)&nfa->l2;

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
static void collect_states(State *s, State **pool, int *count, int max_states) {
    if (s == NULL || s == &matchstate) {
        return;
    }
    
    // すでに登録されているか重複チェック
    for (int i = 0; i < *count; i++) {
        if (pool[i] == s) {
            return;
        }
    }
    
    if (*count >= max_states) {
        return;
    }
    
    pool[(*count)++] = s;
    
    collect_states(s->out, pool, count, max_states);
    collect_states(s->out1, pool, count, max_states);
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
    nfa->state_pool = calloc(nstate, sizeof(State *));
    
    int count = 0;
    collect_states(start, nfa->state_pool, &count, nstate);
    nfa->nstate = count;

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

    List *clist = (List*)&nfa->l1;
    List *nlist = (List*)&nfa->l2;

    // 初期状態リストをセットアップ
    clist->n = 0;
    listid++;
    addstate(clist, nfa->start);

    // 空文字で即マッチ可能（^など）なケースへの対応
    if (ismatch(clist)) {
        return 1;
    }

    // 1文字ずつ走査するシングルパス探索 (時間計算量 O(L))
    for (const unsigned char *p = (const unsigned char*)text; *p; ++p) {
        step(clist, *p, nlist);
        
        // テキストの各開始位置からのマッチングを並列追跡するため、
        // 毎ステップ開始状態(start)をリストに追加する
        addstate(nlist, nfa->start);

        List *tmp = clist;
        clist = nlist;
        nlist = tmp;

        // マッチした時点で即座に 1 を返す
        if (ismatch(clist)) {
            return 1;
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