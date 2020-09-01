#ifndef _KLIBC_UCONTEXT_H
#define _KLIBC_UCONTEXT_H

#include <signal.h>

#define ucontext __ucontext

#ifdef __x86_64__
// We unfortunately have to mix Microsoft's ABI with the SysV ABI
// This is really, really awful, but it works
#define GETSETSWAPCTX_ABI __attribute__((sysv_abi))
#endif

void __makecontext(ucontext_t *, void (*)(void), int, ...);
int __getcontext(ucontext_t *) GETSETSWAPCTX_ABI;
int __setcontext(const ucontext_t *) GETSETSWAPCTX_ABI;
int __swapcontext(ucontext_t *, const ucontext_t *) GETSETSWAPCTX_ABI;

void t_makecontext(ucontext_t*, void (*)(size_t), size_t);
int t_getcontext(ucontext_t *);
int t_setcontext(const ucontext_t *);
int t_swapcontext(ucontext_t *, const ucontext_t *);

void t_ucontext_tests();

#endif

