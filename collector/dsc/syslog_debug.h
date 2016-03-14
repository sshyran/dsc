#ifndef __dsc_syslog_debug_h
#define __dsc_syslog_debug_h

extern int debug_flag;

/* This syslog() macro normally calls the real syslog() function, unless
 * debug_flag is on, in which case it does fprintf to stderr.  It relies on
 * the variable argument count feature of C99 macros.  Unfortunately, C99 does
 * not allow you to use 0 variable args, so where you would normally write
 * syslog(p, "string"), you should instead write syslog(p, "%s", string).
 */

#define syslog(priority, format, ...) \
    do { \
	if (debug_flag) \
	    fprintf(stderr, format "\n", __VA_ARGS__); \
	else \
	    (syslog)(priority, format, __VA_ARGS__); \
    } while (0)


/* This dfprintf() macro won't call syslog(), only fprintf to stderr if
 * debug_flag is on.
 */

#define dfprintf(lvl, format, ...) \
    do { \
	if (debug_flag > lvl) \
	    fprintf(stderr, format "\n", __VA_ARGS__); \
    } while (0)


#endif /* __dsc_syslog_debug_h */