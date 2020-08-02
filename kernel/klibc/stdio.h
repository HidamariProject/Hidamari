#ifndef _KLIBC_STDIO_H
#define _KLIBC_STDIO_H

#include <stddef.h>

extern void __earlyprintk(const char*);
extern void __earlyprintk_num(long long);
extern void __earlyprintk_ptr(const void*);

#define PRIi32 ""
#define PRIu32 ""
#define PRIi64 ""
#define PRIu64 ""

#define vsnprintf(...) 0
#define snprintf(...) 0
#define sprintf(...) 0
#define fprintf(...) 0

#ifndef printf
#define printf(...) 0
#endif

#endif
