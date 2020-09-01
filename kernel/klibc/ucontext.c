#include <stdio.h>
#include <ucontext.h>

// These trampolines are necessary. See `ucontext.h` for more info.
// TODO: disable for non-x86_64+UEFI platforms

int t_setcontext(const ucontext_t* a) {
	return __setcontext(a);
}

int t_getcontext(ucontext_t* a) {
        return __getcontext(a);
}

int t_swapcontext(ucontext_t* a, const ucontext_t* b) {
        return __swapcontext(a, b);
}

static void GETSETSWAPCTX_ABI t_makecontext_cbtrampoline(void (*fn)(size_t), size_t the_arg) {
	fn(the_arg);
}

void t_makecontext(ucontext_t* ctx, void (*fn)(size_t), size_t the_arg) {
	__makecontext(ctx, (void (*)())t_makecontext_cbtrampoline, 2, fn, the_arg);
}
