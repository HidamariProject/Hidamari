#include <ucontext.h>

// Mandatory ucontext trampoline

static int t_swapcontext(ucontext_t* a, const ucontext_t* b) {
        return __swapcontext(a, b);
}

static int t_getcontext(ucontext_t* a) {
        return __getcontext(a);
}

