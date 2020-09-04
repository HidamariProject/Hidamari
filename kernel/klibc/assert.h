#ifndef _KLIBC_ASSERT_H
#define _KLIBC_ASSERT_H

#include <stdlib.h>
#include <stdio.h>

#define assert(n) (!(n)?(__earlyprintk("Oops! " #n " - Assertion failed\r\n"), abort(), 0):0)

#endif
