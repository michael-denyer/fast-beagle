/*
 * bgen_info_value and bgen_info_flag: whole INFO entries only, so a key never
 * matches a longer key it prefixes.
 */
#include <stdio.h>
#include <string.h>

#include "bgen/bgen_writer.h"

static int failures;

static span sp(const char *s) {
    return (span){s, (int)strlen(s)};
}

static void check_value(const char *info, const char *key, const char *want) {
    span got = bgen_info_value(sp(info), key);
    if (got.n != (int)strlen(want) || memcmp(got.s, want, (size_t)got.n) != 0) {
        printf("FAIL value %s in \"%s\": got \"%.*s\", want \"%s\"\n", key, info, got.n, got.s, want);
        ++failures;
    } else {
        printf("pass value %s in \"%s\"\n", key, info);
    }
}

static void check_flag(const char *info, const char *key, bool want) {
    if (bgen_info_flag(sp(info), key) != want) {
        printf("FAIL flag %s in \"%s\": want %s\n", key, info, want ? "present" : "absent");
        ++failures;
    } else {
        printf("pass flag %s in \"%s\"\n", key, info);
    }
}

int main(void) {
    check_value("DR2=0.30;AF=0.0123;IMP", "DR2", "0.30");
    check_value("DR2=0.30;AF=0.0123;IMP", "AF", "0.0123");
    check_flag("DR2=0.30;AF=0.0123;IMP", "IMP", true);
    check_value("DR2=0.30,0.12;AF=0.0123,0.0050", "AF", "0.0123,0.0050");
    check_value("AFX=0.5;AF=0.1", "AF", "0.1");
    check_value("AFX=0.5", "AF", ".");
    check_value("XAF=0.5", "AF", ".");
    check_value("DR2=", "DR2", "");
    check_value("DR2;AF=0.1", "DR2", ".");
    check_flag("DR2;AF=0.1", "DR2", true);
    check_flag("IMPX;DR2=1", "IMP", false);
    check_flag("DR2=1;IMP=1", "IMP", false);
    check_flag("IMP;", "IMP", true);
    check_value("", "DR2", ".");
    check_flag("", "IMP", false);
    check_value(".", "AF", ".");
    check_flag(".", "IMP", false);
    return failures != 0;
}
