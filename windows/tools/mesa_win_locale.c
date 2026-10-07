/*
 * mesa_win_locale.c -- keep the C runtime in the "C" locale (MinGW-w64 / UCRT).
 *
 * libgfortran on MinGW has no uselocale(), so around every I/O statement it does
 *     old = setlocale(LC_NUMERIC, NULL); setlocale(LC_NUMERIC, "C"); ... setlocale(LC_NUMERIC, old);
 * With the UCRT the string "old" is freed by the second call, so the "restore"
 * passes a dangling pointer and the process usually ends up in the user's locale
 * (e.g. Polish_Poland.1250, decimal comma). Under OpenMP, threads then read
 * numbers with strtod() in that locale: "0.6000" is parsed as 0 and MESA stops
 * with "bad header info" while loading the EOS tables.
 *
 * Linked into star.exe together with -static -Wl,--wrap=__imp_setlocale, this
 * wrapper intercepts every setlocale() call of the (static) libgfortran: queries
 * are passed through; a request to set a locale switches the category to "C"
 * once and afterwards only returns the current name (setlocale is expensive in
 * the UCRT and libgfortran calls it twice per I/O statement). The possibly
 * dangling argument is never dereferenced.
 */
#include <stddef.h>
#include <locale.h>

typedef char *(*setlocale_fn)(int, const char *);
extern setlocale_fn __real___imp_setlocale;

static volatile int category_is_c[LC_MAX + 1];

static char *mesa_setlocale(int category, const char *locale)
{
    if (locale == NULL || category < LC_MIN || category > LC_MAX)
        return __real___imp_setlocale(category, locale == NULL ? NULL : "C");
    if (!category_is_c[category]) {
        char *r = __real___imp_setlocale(category, "C");
        if (category == LC_ALL) {
            for (int i = LC_MIN; i <= LC_MAX; i++) category_is_c[i] = 1;
        } else {
            category_is_c[category] = 1;
        }
        return r;
    }
    return __real___imp_setlocale(category, NULL);
}

setlocale_fn __wrap___imp_setlocale = mesa_setlocale;
