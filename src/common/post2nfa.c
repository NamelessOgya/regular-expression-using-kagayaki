#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "nfa.h"

/* マッチ状態: 全フィールドを明示的に初期化 */
// matchstateは、NFAの終端状態を表す。
State matchstate = {
    .c        = Match,
    .out      = NULL,
    .out1     = NULL,
    .lastlist = 0
};

// nstateはnfa_compileなどからも参照できるよう nfa.h で extern 宣言している
int nstate = 0;

// ステートを増やす関数  
State*
state(int c, State *out, State *out1)
{
    State *s; // ステートのポインタを入れる変数を準備  
    
    nstate++; // ステート数を増やす。
    s = malloc(sizeof *s); // ステート用のメモリを確保

    s->lastlist = 0; 
    s->c = c; // ステートに文字をセット
    s->out = out; // 次の状態へのポインタをセット
    s->out1 = out1; // Splitの場合のもう一方のポインタをセット
    return s; // ステートを返す
}

/* 
 * NFAの「作りかけの断片」を管理する構造体。
 * NFAはボトムアップで構築されるため、各断片の「入り口(start)」と
 * 「まだ行き先が決まっていない出口(out)の束」をセットで持ち回る。
 */
typedef struct Frag Frag;
typedef union Ptrlist Ptrlist;

struct Frag
{
    State *start; // この断片の入り口となる状態
    Ptrlist *out; // 出口のポインタリスト（行き先未定の矢印の束）
};

/* Frag構造体を初期化する。 */
Frag
frag(State *start, Ptrlist *out)
{
    Frag n = { start, out };
    return n;
}

/*
 * 行き先未定のポインタを繋いでおくための一時的なリンクリスト構造。
 * Stateの out/out1 変数（行き先が未定のときは使われていない空のポインタ変数）の
 * メモリ空間を直接ハックして、次の未定ポインタへのアドレス(next)を格納する。
 * 行き先が確定した時点で、同じ場所に実際の遷移先アドレス(s)が上書きされ、
 * リストとしての役割は消滅する。非常に巧みな省メモリテクニック。
 */
union Ptrlist
{
    Ptrlist *next; // 行き先未定時: リストの次の要素へのポインタとして利用
    State *s;      // 行き先確定時: 本来のStateへのポインタとして上書き利用
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

/* 
 * 行き先未定だったポインタの束(l)に、確定した行き先状態(s)を一斉にパッチ当て（接続）する。
 * この関数が l->s に確定アドレスを書き込んだ瞬間、l->next として繋がっていたリスト構造は
 * 物理的に上書きされて消滅し、本来のStateポインタとしての機能だけが残る。
 */
void
patch(Ptrlist *l, State *s)
{
    Ptrlist *next;
    
    for(; l; l=next){
        next = l->next; // 上書きで消える前に、リストの次の要素を退避する
        l->s = s;       // 未定だったポインタ変数（箱）に、本来のStateへのアドレスを書き込む
    }
}

/* 
 * 2つの未定ポインタリスト(l1 と l2)を結合する。
 * 例えば a|b のように分岐した経路が合流する際、aを通ったルートとbを通ったルートの
 * どちらの出口も「同じ未定の次の場所」を指すようになるため、ひとつの束にまとめるのに使う。
 */
Ptrlist*
append(Ptrlist *l1, Ptrlist *l2)
{
    Ptrlist *oldl1;
    
    oldl1 = l1;
    while(l1->next)
        l1 = l1->next;
    l1->next = l2;
    return oldl1; // 結合された長いリストの先頭を返す
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
State *post2nfa(char *postfix)
{
    char *p;
    Frag stack[1000], *stackp, e1, e2, e;
    State *s;
    
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
