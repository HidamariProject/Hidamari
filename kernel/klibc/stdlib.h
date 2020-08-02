#ifndef _KLIBC_STDLIB_H
#define _KLIBC_STDLIB_H

#include <stddef.h>
#include <string.h>

#define NORETURN void
extern NORETURN abort();

extern void* malloc(size_t);
extern void* realloc(void*, size_t);
extern void free(void*);

static inline void* calloc(size_t a, size_t b) {
	void *p = malloc(a*b);
	if (!p) return p;
	memset(p, '\0', a*b);
	return p;
}

extern unsigned long strtoul(const char* num, char** __IGNORED__, int base);
extern unsigned long long strtoull(const char* num, char** __IGNORED__, int base);

#endif
