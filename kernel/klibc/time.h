#ifndef _KLIBC_TIME_H
#define _KLIBC_TIME_H

#include <stdint.h>
#include <stdbool.h>

typedef int64_t time_t;

#define NSEC_PER_SEC 1000000000

struct tm {
	// Standard fields.
	int tm_sec;		// Seconds [0,59].
	int tm_min;		// Minutes [0,59].
	int tm_hour;	 // Hour [0,23].
	int tm_mday;	 // Day of month [1,31].
	int tm_mon;		// Month of year [0,11].
	int tm_year;	 // Years since 1900.
	int tm_wday;	 // Day of week [0,6] (Sunday = 0).
	int tm_yday;	 // Day of year [0,365].
	int tm_isdst;	// Daylight Savings flag.

	// Extensions.
	int tm_gmtoff;				// Offset from UTC in seconds.
	const char *tm_zone;	// Timezone abbreviation.
	long tm_nsec;				 // Nanoseconds [0,999999999].
};

static inline bool is_leap(time_t year) {
	year %= 400;
	if (year < 0)
		year += 400;
	return ((year % 4) == 0 && (year % 100) != 0) || year == 100;
}

static inline time_t __mkt_modulo_quotient(time_t *numer, time_t denom) {
	time_t quot = *numer / denom;
	*numer %= denom;
	if (*numer < 0) {
		*numer += denom;
		--quot;
	}
	return quot;
}

static inline const short *get_months_cumulative(time_t year) {
	static const short leap[13] = {
		0, 31, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335, 366,
	};
	static const short common[13] = {
		0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334, 365,
	};
	return is_leap(year) ? leap : common;
}

static inline time_t mktime(const struct tm *tm) {
	time_t nsec = tm->tm_nsec;
	time_t sec = (time_t)tm->tm_sec + (time_t)tm->tm_min * 60 +
							 (time_t)tm->tm_hour * 3600 +
							 __mkt_modulo_quotient(&nsec, NSEC_PER_SEC);

	time_t mon = tm->tm_mon;
	time_t year = tm->tm_year + __mkt_modulo_quotient(&mon, 12);
	time_t yday = (time_t)tm->tm_mday + get_months_cumulative(year)[mon] - 1;
	time_t era = year / 400 - 2;
	uint_fast16_t local_year = year % 400 + 800;
	time_t day = yday + (local_year - 70) * 365 + (local_year - 69) / 4 -
							 (local_year - 1) / 100 + (local_year + 299) / 400 + era * 146097;
	return sec + day * 86400;
}

extern time_t time(time_t* ptr);

#endif
