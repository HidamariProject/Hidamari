#ifndef _KLIBC_MATH_H
#define _KLIBC_MATH_H

#define NAN -(42) /* TODO */
#define isnan(x) 0

extern double ceil(double x);
extern double fabs(double x);
extern double floor(double x);
extern double rint(double x);
extern double sqrt(double x);
extern double sin(double x);
extern double trunc(double x);

#define _FLOATIFY(fn, var) ((float)fn((double)(var)))
#define ceilf(x) _FLOATIFY(ceil, x)
#define fabsf(x) _FLOATIFY(fabs, x)
#define floorf(x) _FLOATIFY(floor, x)
#define rintf(x) _FLOATIFY(rint, x)
#define sqrtf(x) _FLOATIFY(sqrt, x)
#define sinf(x) _FLOATIFY(sin, x)
#define truncf(x) _FLOATIFY(trunc, x)

// This is technically wrong, but whatever
#define signbit(n) ((n) < 0.0f ? 1 : 0)

static inline double copysign(double a, double b) {
	int isNeg = signbit(b);
	return isNeg ? (a * -1) : a;
}

#define copysignf(a, b) ((float)copysign((double)(a), (double)(b)))

#endif
