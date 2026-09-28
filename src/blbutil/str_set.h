/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef BLBUTIL_STR_SET_H
#define BLBUTIL_STR_SET_H

#include <stdbool.h>
#include <stddef.h>

/* A set of strings mapped to consecutive indices in insertion order. Stands in
 * for Java's HashSet<String> and HashMap<String,Integer>; Beagle only looks up
 * these collections and never iterates them, so their order is not observable. */
typedef struct str_set str_set;

str_set *str_set_new(void);
/* Returns the index of s, adding it with the next index if absent. */
int str_set_index(str_set *set, const char *s, size_t len);
/* Returns the index of s, or -1 if absent. */
int str_set_find(const str_set *set, const char *s, size_t len);
int str_set_size(const str_set *set);
const char *str_set_get(const str_set *set, int index);
void str_set_free(str_set *set);

#endif
