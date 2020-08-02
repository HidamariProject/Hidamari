// Platform sanity tests

extern void __earlyprintk(const char*);
extern void abort();

volatile struct __sanityCheckStruct {
	char a, b, c;
	int d, e;
	long long f, g, h, i;
	short j, k, l;
	unsigned short m, n;
	long p;
	char r[8];
	short s[2];
	char t, u, v;
	int w[4];
	long long x[1];
	long y[2];
	char z;
} __global_sanityCheckStruct;

void structSanityCheck() {
	volatile struct __sanityCheckStruct a = __global_sanityCheckStruct;
	volatile struct __sanityCheckStruct b;
	volatile static struct __sanityCheckStruct c;
	c = b; // uninitialized -> local (static) should be OK
	c = a; // local (static) -> static should be OK
	b = a; // static -> local (stack) should be OK
	c = b; // local (stack) -> local (static) should be OK
	// success
}

volatile int __global_sanityCheckIntArray[42];

void intArraySanityCheck() {
	volatile int* ptr = &__global_sanityCheckIntArray[5];
	*ptr = 96;
	if (__global_sanityCheckIntArray[5] != 96) abort();
	volatile long long* ptr2 = (long long*) &__global_sanityCheckIntArray[21];
	*ptr2 = 87;
	*ptr2 = *ptr;
	if (*ptr != *ptr2) abort();
	/// success
}

void allSanityChecks() {
	structSanityCheck();
	intArraySanityCheck();
}
