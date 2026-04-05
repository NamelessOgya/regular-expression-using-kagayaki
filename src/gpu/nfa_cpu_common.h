/* =======================================================================
 *  sandbox/nfa_cpu_common.h
 *  -------------------------------------------------
 *  Thompson‑NFA ― 正規表現を NFA に変換する CPU 部分だけを
 *  切り出したヘッダ。CUDA 版 (nfa.cu) からインクルードして使用する。
 *  MIT License (原著: Russ Cox, 2007)
 * =======================================================================*/
 #pragma once
 
 #include <cstdio>
 #include <cstdlib>
 #include <cstring>
 
 /*--------------------------- 基本型・定数 ------------------------------*/
 enum { Match = 256, Split = 257 };
 
 struct State {
     int   c;
     State *out;
     State *out1;
     int   lastlist;
 };
 
 extern int   nstate;
 extern State matchstate;
 
 /*--------------------------- re2post -----------------------------------*/
static inline char* re2post(char *re)
{
    int num_alt = 0;
    int num_atom = 0;
    static char postfix_buffer[8000];
    char *dest = postfix_buffer;
    
    struct {
        int num_alt;
        int num_atom;
    } parentheses[100];
    
    int paren_index = 0;
    
    if (strlen(re) >= sizeof(postfix_buffer) / 2) {
        return nullptr;
    }
    
    for (char *current_char = re; *current_char != '\0'; current_char++) {
        switch (*current_char) {
        case '(':
            if (num_atom > 1) {
                num_atom--;
                *dest = '.';
                dest++;
            }
            if (paren_index >= 100) {
                return nullptr;
            }
            parentheses[paren_index].num_alt = num_alt;
            parentheses[paren_index].num_atom = num_atom;
            paren_index++;
            num_alt = 0;
            num_atom = 0;
            break;
            
        case '|':
            if (num_atom == 0) {
                return nullptr;
            }
            while (num_atom > 1) {
                num_atom--;
                *dest = '.';
                dest++;
            }
            num_atom = 0;
            num_alt++;
            break;
            
        case ')':
            if (paren_index == 0 || num_atom == 0) {
                return nullptr;
            }
            while (num_atom > 1) {
                num_atom--;
                *dest = '.';
                dest++;
            }
            for (; num_alt > 0; num_alt--) {
                *dest = '|';
                dest++;
            }
            paren_index--;
            num_alt = parentheses[paren_index].num_alt;
            num_atom = parentheses[paren_index].num_atom;
            num_atom++;
            break;
            
        case '*':
        case '+':
        case '?':
            if (num_atom == 0) {
                return nullptr;
            }
            *dest = *current_char;
            dest++;
            break;
            
        default:
            if (num_atom > 1) {
                num_atom--;
                *dest = '.';
                dest++;
            }
            *dest = *current_char;
            dest++;
            num_atom++;
            break;
        }
    }
    
    if (paren_index != 0) {
        return nullptr;
    }
    
    while (num_atom > 1) {
        num_atom--;
        *dest = '.';
        dest++;
    }
    
    for (; num_alt > 0; num_alt--) {
        *dest = '|';
        dest++;
    }
    
    *dest = '\0';
    return postfix_buffer;
}
 
 /*--------------------------- NFA 構築ユーティリティ --------------------*/
 inline State* state(int c, State *out, State *out1)
 {
     ++nstate;
     State *s   = (State*) std::malloc(sizeof *s);
     s->c = c; s->out = out; s->out1 = out1; s->lastlist = 0;
     return s;
 }
 
 union Ptrlist { Ptrlist *next; State *s; };
 struct Frag { State *start; Ptrlist *out; };
 
 inline Frag frag(State *start, Ptrlist *out) { return { start, out }; }
 inline Ptrlist* list1(State **outp) { Ptrlist *l=(Ptrlist*)outp; l->next=nullptr; return l; }
 inline void patch(Ptrlist *l, State *s) { for (Ptrlist *n; l; l=n){ n=l->next; l->s=s; } }
 inline Ptrlist* append(Ptrlist *l1, Ptrlist *l2)
 { Ptrlist *o=l1; while (l1->next) l1=l1->next; l1->next=l2; return o; }
 
 /*--------------------------- post2nfa ----------------------------------*/
 inline State* post2nfa(char *postfix)
 {
     if (!postfix) return nullptr;
     Frag st[1000], *sp = st;
 #   define PUSH(x) (*sp++ = (x))
 #   define POP()   (*--sp)
 
     for (char *p=postfix; *p; ++p) {
         switch (*p) {
         default: {
             State *s = state(*p, nullptr, nullptr);
             PUSH(frag(s, list1(&s->out))); break; }
         case '.': {
             Frag e2=POP(), e1=POP(); patch(e1.out,e2.start);
             PUSH(frag(e1.start,e2.out)); break; }
         case '|': {
             Frag e2=POP(), e1=POP(); State *s=state(Split,e1.start,e2.start);
             PUSH(frag(s,append(e1.out,e2.out))); break; }
         case '?': {
             Frag e=POP(); State *s=state(Split,e.start,nullptr);
             PUSH(frag(s,append(e.out,list1(&s->out1)))); break; }
         case '*': {
             Frag e=POP(); State *s=state(Split,e.start,nullptr);
             patch(e.out,s); PUSH(frag(s,list1(&s->out1))); break; }
         case '+': {
             Frag e=POP(); State *s=state(Split,e.start,nullptr);
             patch(e.out,s); PUSH(frag(e.start,list1(&s->out1))); break; }
         }
     }
     Frag e = POP();
     if (sp != st) return nullptr;
     patch(e.out, &matchstate);
     return e.start;
 #   undef PUSH
 #   undef POP
 }
 

 