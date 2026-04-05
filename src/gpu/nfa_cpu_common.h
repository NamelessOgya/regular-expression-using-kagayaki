/* =======================================================================
 *  sandbox/nfa_cpu_common.h
 *  -------------------------------------------------
 *  Thompson‑NFA ― 正規表現を NFA に変換する CPU 部分だけを
 *  切り出したヘッダ。CUDA 版 (nfa.cu) からインクルードして使用する。
 *  MIT License (原著: Russ Cox, 2007)
 * =======================================================================*/
 #ifndef NFA_CPU_COMMON_H
 #define NFA_CPU_COMMON_H
 
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
     int nalt = 0, natom = 0;
     static char buf[8000];
     char *dst  = buf;
 
     struct { int nalt, natom; } paren[100], *p = paren;
     if (strlen(re) >= sizeof buf / 2) return nullptr;
 
     for (; *re; ++re) {
         switch (*re) {
         case '(':
             if (natom > 1) { --natom; *dst++ = '.'; }
             if (p >= paren + 100) return nullptr;
             p->nalt = nalt;  p->natom = natom;  ++p;
             nalt = natom = 0; break;
         case '|':
             if (natom == 0) return nullptr;
             while (--natom > 0) *dst++ = '.';
             ++nalt; break;
         case ')':
             if (p == paren || natom == 0) return nullptr;
             while (--natom > 0) *dst++ = '.';
             for (; nalt > 0; --nalt) *dst++ = '|';
             --p;  nalt = p->nalt;  natom = ++p->natom; break;
         case '*': case '+': case '?':
             if (natom == 0) return nullptr;
             *dst++ = *re; break;
         default:
             if (natom > 1) { --natom; *dst++ = '.'; }
             *dst++ = *re; ++natom; break;
         }
     }
     if (p != paren) return nullptr;
     while (--natom > 0) *dst++ = '.';
     for (; nalt > 0; --nalt) *dst++ = '|';
     *dst = '\0';
     return buf;
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
 
 #endif /* NFA_CPU_COMMON_H */
 