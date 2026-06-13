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
 * 基本的には作られたStateはFragの形に統合される。  
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
union Ptrlist  // unionは一つのメモリ空間を複数の違う型でシェアする。 nextかsのどちらかしか持てない。  
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
 * `re2post` で作成された後置表現（逆ポーランド記法）を左から右へ1文字ずつ読み込みます。
 * Thompsonのアルゴリズムに基づき、「未完成のNFAの断片（Frag）」をスタックに積んだり
 * 取り出したりしながら、最終的に1つの巨大な迷路（Stateのネットワーク）を組み上げます。
 * 
 * [想定I/O]
 * - input:  後置表現文字列 (例: "ab|*c#" など)
 * - output: 構築されたNFAの「入り口」となる状態 (State *) へのポインタ
 * 
 * ▼ 記号ごとの状態遷移（スタック操作）の解説
 * ※ 各ケースにおいて、スタックから Frag を取り出し(pop)、新しい Frag を作成して積み直し(push)ます。
 * 
 * 1. 【基本文字 (例: 'a')】:
 *    - その文字に対する単一の State を作成し、未来への出口を未確定のままスタックに積みます。
 * 
 * 2. 【結合 '#'】: (例: e1 e2 #)
 *    - e1の出口をe2の入り口に直接繋ぎ(patch)、一筆書きの新しい長い断片としてスタックに戻します。
 * 
 * 3. 【選択 '|'】: (例: e1 e2 |)
 *    - 入り口を2つに分岐させる『Split状態』を作ります。
 *    - Splitの出口をそれぞれ「e1の入り口」と「e2の入り口」に繋ぎ、出口同士の束を1つにまとめて(append)スタックに戻します。
 * 
 * 4. 【0回以上の繰り返し '*'】: (例: e *)
 *    - 入り口を分岐させる『Split状態』を作り、「eを通るルート」と「eを避ける空ルート」へ繋ぎます。
 *    - さらに、eを通り終わった後の出口を再び入り口(Split)へ戻るように繋ぎ(patch)、無限ループを完成させます。
 * 
 * 5. 【1回以上の繰り返し '+'】: (例: e +)
 *    - '*' に似ていますが、ループの入り口が「eの開始地点」になるため、最低1回は強制的に e を通過することになります。
 */
State *post2nfa(char *postfix)
{
    char *p;
    Frag stack[1000], *stackp, e1, e2, e;
    State *s;
    
    if(postfix == NULL)
        return NULL;

    nstate = 0; // Reset global state count for the new NFA compilation



    /* スタックへ積む・取り出す マクロ */
    #define push(s) *stackp++ = s
    #define pop() *--stackp

    stackp = stack;
    for(p=postfix; *p; p++){
        switch(*p){
        case '.':  /* ワイルドカード */
            /* 
             * Any（文字に関わらず通過できる特別な状態）を作り出してスタックに積みます。
             * 出口（s->out）は未決定として list1() で束にしておきます。
             */
            s = state(Any, NULL, NULL);
            push(frag(s, list1(&s->out)));
            break;
        case '#':	/* 結合 (catenate) */
            /* 後置表現なので、スタックには [..., e1, e2] の順で積まれている。上のe2から逆に取り出す。 */
            e2 = pop();
            e1 = pop();
            /* e1の未確定な出口を、e2の入り口へと確定させ接続する（e1 -> e2） */
            patch(e1.out, e2.start);
            /* e1から入って、e2の出口へと抜ける新しい長い断片としてスタックに戻す */
            push(frag(e1.start, e2.out));
            break;
        case '|':	/* 選択 (alternate) */
            e2 = pop();
            e1 = pop();
            /* 経路を2つに分岐する Split（名無し）状態を作成し、それぞれの入り口に繋ぐ */
            s = state(Split, e1.start, e2.start);
            /* e1を通った後、e2を通った後、どちらも「次の行き先は共通」なので未定の出口を束ねる(append) */
            push(frag(s, append(e1.out, e2.out)));
            break;
        case '?':	/* 0回または1回 (zero or one) */
            e = pop();
            /* 分岐を作成し、片方は e の入り口へ。もう片方は NULL(空ルート: eを避ける) へ繋ぐ */
            s = state(Split, e.start, NULL);
            /* 「eを通った後の出口」と「空ルートの出口」の2本を束ねて未来に託す */
            push(frag(s, append(e.out, list1(&s->out1))));
            break;
        case '*':	/* 0回以上の繰り返し (zero or more) */
            e = pop();
            /* 分岐を作成し、片方は e へ(ループ用)、もう片方は空ルートとして未来へ繋ぐ */
            s = state(Split, e.start, NULL);
            /* 最も重要なトリック：eを通った後の出口を自分自身(s)に向けて書き換え、ぐるぐる回るループを作る */
            patch(e.out, s);
            /* この断片は s から入り、もう一方の分岐(s->out1)から未来へ脱出するので、それをスタックに積む */
            push(frag(s, list1(&s->out1)));
            break;
        case '+':	/* 1回以上の繰り返し (one or more) */
            e = pop();
            /* eを通り終わった後に「もう一度eをやるか？(ループ)」の分岐(Split)を作成する.まだ決まってない場合はNULLという約束。 */
            s = state(Split, e.start, NULL);
            /* 文字通り「eの出口」を分岐状態(s)に直結させる */
            patch(e.out, s);
            /* この断片の入り口は必ず e.start (最低1回は通過する)。出口は分岐(s->out1)の未来パスとなる */
            push(frag(e.start, list1(&s->out1)));
            break;
        default:
            /* 
             * 通常の文字（オペランド）に対する処理。
             * a, b, c などの実際の文字状態を作成し、即座にスタックに積みます。
             */
            s = state((unsigned char)*p, NULL, NULL);
            push(frag(s, list1(&s->out)));
            break;
        }
    }

    /* ループが終わると、スタックには【完成した1つの巨大な迷路の断片】が残るはず */
    e = pop();
    if(stackp != stack)
        return NULL; /* 正規表現の構文エラー（演算子と文字の対応がおかしかった場合） */

    /* 完全に完成したNFAの「未確定な出口」すべてに、ゴールの標識（Match状態）をパッチして終端をつなぐ */
    patch(e.out, &matchstate);
    
    /* 完成したNFAグラフの先頭状態を返す */
    return e.start;
#undef pop
#undef push
}
