nvcc -O3 -arch=sm_80 -Isandbox sandbox/nfa.cu -o nfa.out
gcc  -O3 -DGPU_RUN src/test_nfa.c -o test_nfa.out
./test_nfa.out