/*
 * Copyright (c) 2018, 2020 Ariadne Conill <ariadne@dereferenced.org>
 *
 * Permission to use, copy, modify, and/or distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * This software is provided 'as is' and without any warranty, express or
 * implied.  In no event shall the authors be liable for any damages arising
 * from the use of this software.
 */

#define _GNU_SOURCE
#include <stddef.h>
#include <stdarg.h>
#include <signal.h>
#include <string.h>
#include <stdint.h>


#include "defs.h"


extern void __start_context(void);
extern int __setcontext(const ucontext_t *ucp);


void
__makecontext(ucontext_t *ucp, void (*func)(void), int argc, ...)
{
	greg_t *sp;
	va_list va;
	int i;

	sp = (greg_t *) ((uintptr_t) ucp->uc_stack.ss_sp + ucp->uc_stack.ss_size);
	sp = (greg_t *) (((uintptr_t) sp & -8L));

	ucp->uc_mcontext.gregs[7]  = (uintptr_t) func;
	ucp->uc_mcontext.gregs[8]  = (uintptr_t) ucp->uc_link;
	ucp->uc_mcontext.gregs[9]  = (uintptr_t) &__setcontext;
	ucp->uc_mcontext.gregs[14] = (uintptr_t) &__start_context;

	va_start(va, argc);

	for (i = 0; i < argc && i < 5; i++)
		ucp->uc_mcontext.gregs[i + 2] = va_arg (va, greg_t);

	if (argc > 5)
	{
		sp -= argc - 5;

		for (i = 5; i < argc; i++)
			sp[i - 5] = va_arg (va, greg_t);
	}

	va_end(va);

	/* make room for backchain / register save area */
	sp -= 20;
	*sp = 0;

	/* set up %r15 as sp */
	ucp->uc_mcontext.gregs[15] = (uintptr_t) sp;
}


extern __typeof(__makecontext) makecontext __attribute__((weak, __alias__("__makecontext")));
