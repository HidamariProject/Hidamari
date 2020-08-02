#ifndef _KLIBC_ASSERT_H
#define _KLIBC_ASSERT_H

#include <stdlib.h>

#define assert(n) (!(n)?(__earlyprintk(#n " - Assertion failed\r\n"), abort(), 0):0)

#endif
