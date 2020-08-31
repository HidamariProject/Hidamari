#ifndef _KLIBC_UCONTEXT_H
#define _KLIBC_UCONTEXT_H

#include <signal.h>

#define ucontext __ucontext

void __makecontext(ucontext_t *, void (*)(void), int, ...);
int __getcontext(ucontext_t *) __attribute((sysv_abi));
int __setcontext(const ucontext_t *) __attribute((sysv_abi));
int __swapcontext(ucontext_t *, const ucontext_t *) __attribute((sysv_abi));

int t_getcontext(ucontext_t *);
int t_setcontext(const ucontext_t *);
int t_swapcontext(ucontext_t *, const ucontext_t *);

#endif

