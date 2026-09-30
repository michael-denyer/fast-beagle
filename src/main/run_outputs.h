/* SPDX-License-Identifier: GPL-3.0-or-later */
#ifndef MAIN_RUN_OUTPUTS_H
#define MAIN_RUN_OUTPUTS_H

#include <stdio.h>

#include "main/par.h"

/* fast-beagle's destinations and failure cleanup. One owner per run; create
 * it before starting readers and free it only after every reader and writer
 * has finished. Paths are immutable and borrowed by their format writers. */
typedef struct run_outputs run_outputs;
typedef enum {
    RUN_OUTPUT_VCF, RUN_OUTPUT_LOG, RUN_OUTPUT_BGEN, RUN_OUTPUT_INFO,
    RUN_OUTPUT_SAMPLE, RUN_OUTPUT_TBI, RUN_OUTPUT_COUNT
} run_output_file;
typedef enum { RUN_BGEN_DATA, RUN_BGEN_INFO, RUN_BGEN_SAMPLE } run_bgen_file;

/* Check enabled destinations against inputs without opening files or
 * registering cleanup. Called at the existing parameter validation point. */
void run_outputs_check(const par *p);
run_outputs *run_outputs_new(const par *p);
/* Optional destinations are NULL when disabled. out must outlive the path. */
const char *run_outputs_path(const run_outputs *out, run_output_file file);
/* Open in wb mode and register creation together with respect to fatal
 * cleanup. Returns NULL on an open error or after terminal cleanup. The
 * caller owns the stream and reports errors after this helper unlocks. */
FILE *run_outputs_bgen_open(run_outputs *out, run_bgen_file file);
/* Immediately after all BGEN members have been written and closed. A later
 * process failure retains them. Completion cannot reverse terminal cleanup. */
void run_outputs_bgen_complete(run_outputs *out);
/* After the VCF header succeeds, remove an old enabled index best-effort. */
void run_outputs_invalidate_index(run_outputs *out);
void run_outputs_free(run_outputs *out);

#endif
