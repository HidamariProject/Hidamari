#ifndef _KLIBC_STRING_H
#define _KLIBC_STRING_H

#include <stddef.h>

extern int strcmp(const char*, const char*);
extern size_t strlen(const char*);
extern char* strcat(char*, const char*);

extern void* _klibc_memset(void*, int, size_t);
#define memset _klibc_memset
extern void* _klibc_memcpy(void*, const void*, size_t);
#define memcpy _klibc_memcpy
extern int memcmp(const void*, const void*, size_t);

#endif
