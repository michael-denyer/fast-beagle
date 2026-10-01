------------------------------ MODULE FatalExit ------------------------------
(***************************************************************************)
(* The fatal-error lifecycle of util_exit in src/blbutil/utilities.c       *)
(* across threads. A thread inside util_try that calls util_exit longjmps  *)
(* back to its try frame with the message stored; the consumer of that     *)
(* frame raises it later (sliding_window_next, block_reader_next,          *)
(* vcf_it_next). A thread outside util_try that calls util_exit tests the  *)
(* exiting flag: set, it pauses forever; clear, it calls exit(), which runs *)
(* the atexit handler remove_partial in src/bgen/bgen_files.c and ends the *)
(* process. A longjmp out of a critical section leaves the mutex owned by  *)
(* a frame that no longer exists, and every later lock blocks forever.     *)
(* trace.c and chrom_ids.c unlock before util_exit; ChromLeaksLock = TRUE  *)
(* reproduces the chrom_ids.c that did not.                                *)
(*                                                                         *)
(* Threads: main, the read-ahead reader (read_windows runs under util_try  *)
(* on it), and parallel_for workers that enter util_try per parse task.    *)
(* owner is the mutex's truth; holds is what the thread's live frames      *)
(* know. They differ only after a longjmp that leaked a lock.              *)
(***************************************************************************)
EXTENDS FiniteSets

CONSTANTS Workers, ChromLeaksLock

ASSUME Workers # {} /\ ChromLeaksLock \in BOOLEAN

Main == "main"
Reader == "reader"
Threads == {Main, Reader} \cup Workers
Locks == {"bgen", "chrom"}
Members == {"bgen", "info", "sample"}
None == "none"

VARIABLES
    proc,       \* "running", "exiting" (inside exit()), "exit1" or "exit0"
    exiting,    \* the atomic_flag in util_exit
    pc,         \* per thread: "run", "wait" (on a mutex), "paused", "exit", "done"
    inTry,      \* per thread: inside a util_try frame
    holds,      \* per thread: the lock its live frames hold, or None
    want,       \* per thread: the lock it is blocked on, or None
    owner,      \* per lock: the thread owning the mutex, or None
    deferred,   \* per thread: "none", "pending", "raised" or "discarded"
    created,    \* BGEN members bgen_files_open created
    completed,  \* bgen_files_complete ran
    cleaned,    \* remove_partial ran
    removed     \* members remove_partial removed

vars == <<proc, exiting, pc, inTry, holds, want, owner, deferred, created,
          completed, cleaned, removed>>

TypeOK ==
    /\ proc \in {"running", "exiting", "exit1", "exit0"}
    /\ exiting \in BOOLEAN
    /\ pc \in [Threads -> {"run", "wait", "paused", "exit", "done"}]
    /\ inTry \in [Threads -> BOOLEAN]
    /\ holds \in [Threads -> Locks \cup {None}]
    /\ want \in [Threads -> Locks \cup {None}]
    /\ owner \in [Locks -> Threads \cup {None}]
    /\ deferred \in [Threads -> {"none", "pending", "raised", "discarded"}]
    /\ created \subseteq Members
    /\ completed \in BOOLEAN
    /\ cleaned \in BOOLEAN
    /\ removed \subseteq Members

Init ==
    /\ proc = "running"
    /\ exiting = FALSE
    /\ pc = [t \in Threads |-> "run"]
    /\ inTry = [t \in Threads |-> t = Reader]
    /\ holds = [t \in Threads |-> None]
    /\ want = [t \in Threads |-> None]
    /\ owner = [l \in Locks |-> None]
    /\ deferred = [t \in Threads |-> "none"]
    /\ created = {}
    /\ completed = FALSE
    /\ cleaned = FALSE
    /\ removed = {}

Finished == completed \/ cleaned
Live == proc \in {"running", "exiting"}
BgenUnchanged == UNCHANGED <<created, completed, cleaned, removed>>

(* pthread_mutex_lock: take a free mutex, or block on a held one. *)
Lock(t, l) ==
    /\ Live /\ pc[t] = "run" /\ holds[t] = None
    /\ IF owner[l] = None
         THEN /\ owner' = [owner EXCEPT ![l] = t]
              /\ holds' = [holds EXCEPT ![t] = l]
              /\ UNCHANGED <<pc, want>>
         ELSE /\ pc' = [pc EXCEPT ![t] = "wait"]
              /\ want' = [want EXCEPT ![t] = l]
              /\ UNCHANGED <<owner, holds>>
    /\ UNCHANGED <<proc, exiting, inTry, deferred>> /\ BgenUnchanged

(* A blocked thread gets the mutex once it is free. *)
Acquire(t) ==
    /\ Live /\ pc[t] = "wait" /\ owner[want[t]] = None
    /\ owner' = [owner EXCEPT ![want[t]] = t]
    /\ holds' = [holds EXCEPT ![t] = want[t]]
    /\ want' = [want EXCEPT ![t] = None]
    /\ pc' = [pc EXCEPT ![t] = "run"]
    /\ UNCHANGED <<proc, exiting, inTry, deferred>> /\ BgenUnchanged

Unlock(t) ==
    /\ Live /\ pc[t] = "run" /\ holds[t] # None
    /\ owner' = [owner EXCEPT ![holds[t]] = None]
    /\ holds' = [holds EXCEPT ![t] = None]
    /\ UNCHANGED <<proc, exiting, pc, want, inTry, deferred>> /\ BgenUnchanged

(* bgen_files_open under its lock: creates nothing once finished. *)
Open(t, m) ==
    /\ Live /\ pc[t] = "run" /\ holds[t] = None /\ owner["bgen"] = None
    /\ m \notin created
    /\ created' = IF Finished THEN created ELSE created \cup {m}
    /\ UNCHANGED <<proc, exiting, pc, inTry, holds, want, owner, deferred,
                   completed, cleaned, removed>>

(* parallel_for parse tasks run under util_try (block_reader.c:75,
   vcf_it.c:112). The reader is under util_try for its whole life
   (sliding_window.c:415). *)
EnterTry(w) ==
    /\ Live /\ pc[w] = "run" /\ ~inTry[w] /\ holds[w] = None
    /\ inTry' = [inTry EXCEPT ![w] = TRUE]
    /\ UNCHANGED <<proc, exiting, pc, holds, want, owner, deferred>> /\ BgenUnchanged

LeaveTry(w) ==
    /\ Live /\ pc[w] = "run" /\ inTry[w] /\ holds[w] = None
    /\ inTry' = [inTry EXCEPT ![w] = FALSE]
    /\ UNCHANGED <<proc, exiting, pc, holds, want, owner, deferred>> /\ BgenUnchanged

(* The mutex owner after util_exit unwinds the frame that locked it.
   ChromLeaksLock = TRUE is the earlier chrom_ids.c, which called
   str_set_index under the lock and so util_exit on out of memory.
   ChromLeaksLock = FALSE is the code now: chrom_ids_index calls
   str_set_try_index, unlocks, then exits, as trace.c:42 unlocks before
   util_exit. No util_exit runs under the bgen_files lock. *)
Released(t) ==
    \/ holds[t] = None
    \/ holds[t] = "chrom" /\ ~ChromLeaksLock

OwnerAfterExit(t) ==
    IF Released(t) /\ holds[t] # None THEN [owner EXCEPT ![holds[t]] = None] ELSE owner

(* util_exit inside util_try: store the message, longjmp to the try frame.
   The reader's frame is read_ahead, which parks the error and returns
   (sliding_window.c:416-423). A worker's frame is parse_task, which keeps
   the error for the consumer and goes on to the next item. *)
FailInTry(t) ==
    /\ Live /\ pc[t] = "run" /\ inTry[t] /\ holds[t] # "bgen"
    /\ deferred' = [deferred EXCEPT ![t] = "pending"]
    /\ inTry' = [inTry EXCEPT ![t] = FALSE]
    /\ owner' = OwnerAfterExit(t)
    /\ holds' = [holds EXCEPT ![t] = None]
    /\ pc' = [pc EXCEPT ![t] = IF t = Reader THEN "done" ELSE "run"]
    /\ UNCHANGED <<proc, exiting, want>> /\ BgenUnchanged

(* util_exit outside util_try (utilities.c:65-81): the second exiting thread
   pauses forever; the first calls exit(). *)
FatalExit(t) ==
    /\ exiting' = TRUE
    /\ IF exiting
         THEN /\ pc' = [pc EXCEPT ![t] = "paused"]
              /\ UNCHANGED proc
         ELSE /\ pc' = [pc EXCEPT ![t] = "exit"]
              /\ proc' = "exiting"
    /\ owner' = OwnerAfterExit(t)
    /\ holds' = [holds EXCEPT ![t] = None]

FailOutsideTry(t) ==
    /\ Live /\ pc[t] = "run" /\ ~inTry[t] /\ holds[t] # "bgen"
    /\ FatalExit(t)
    /\ UNCHANGED <<inTry, want, deferred>> /\ BgenUnchanged

(* exit() runs remove_partial (bgen_files.c:14-21) under the bgen lock,
   then the process ends with status 1. *)
RunExit(t) ==
    /\ proc = "exiting" /\ pc[t] = "exit" /\ owner["bgen"] = None
    /\ removed' = IF Finished THEN removed ELSE created
    /\ cleaned' = TRUE
    /\ proc' = "exit1"
    /\ pc' = [pc EXCEPT ![t] = "done"]
    /\ UNCHANGED <<exiting, inTry, holds, want, owner, deferred, created, completed>>

(* The reader finishes its windows and returns normally. *)
ReaderDone ==
    /\ Live /\ pc[Reader] = "run" /\ holds[Reader] = None
    /\ pc' = [pc EXCEPT ![Reader] = "done"]
    /\ inTry' = [inTry EXCEPT ![Reader] = FALSE]
    /\ UNCHANGED <<proc, exiting, holds, want, owner, deferred>> /\ BgenUnchanged

(* A worker thread returns to parallel_for's join. *)
WorkerDone(w) ==
    /\ Live /\ pc[w] = "run" /\ ~inTry[w] /\ holds[w] = None
    /\ pc' = [pc EXCEPT ![w] = "done"]
    /\ UNCHANGED <<proc, exiting, inTry, holds, want, owner, deferred>> /\ BgenUnchanged

(* The reader takes a parsed block after parallel_for joined its workers and
   raises the first stored parse error (block_reader.c:198-200,
   vcf_it.c:131), still under its own util_try. *)
ConsumeWorker(w) ==
    /\ Live /\ pc[Reader] = "run" /\ inTry[Reader] /\ holds[Reader] = None
    /\ deferred[w] = "pending"
    /\ \A v \in Workers : pc[v] = "done"
    /\ deferred' = [deferred EXCEPT ![w] = "raised", ![Reader] = "pending"]
    /\ inTry' = [inTry EXCEPT ![Reader] = FALSE]
    /\ pc' = [pc EXCEPT ![Reader] = "done"]
    /\ UNCHANGED <<proc, exiting, holds, want, owner>> /\ BgenUnchanged

(* sliding_window_next raises the reader's parked error on the main thread,
   outside any util_try (sliding_window.c:437). *)
MainTake ==
    /\ Live /\ pc[Main] = "run" /\ holds[Main] = None
    /\ deferred[Reader] = "pending"
    /\ deferred' = [deferred EXCEPT ![Reader] = "raised"]
    /\ FatalExit(Main)
    /\ UNCHANGED <<inTry, want>> /\ BgenUnchanged

(* After the last window: window_writer_close completes the BGEN members
   (bgen_writer.c:682), sliding_window_close joins the reader and frees
   parse errors of blocks never taken (block_reader_close), main returns 0. *)
MainClose ==
    /\ Live /\ pc[Main] = "run" /\ holds[Main] = None /\ owner["bgen"] = None
    /\ pc[Reader] = "done" /\ deferred[Reader] # "pending"
    /\ \A w \in Workers : pc[w] = "done"
    /\ deferred' = [t \in Threads |-> IF deferred[t] = "pending" THEN "discarded" ELSE deferred[t]]
    /\ completed' = TRUE
    /\ proc' = "exit0"
    /\ pc' = [pc EXCEPT ![Main] = "done"]
    /\ UNCHANGED <<exiting, inTry, holds, want, owner, created, cleaned, removed>>

Ended == proc \in {"exit1", "exit0"} /\ UNCHANGED vars

Next ==
    \/ \E t \in Threads :
        \/ \E l \in Locks : Lock(t, l)
        \/ \E m \in Members : Open(t, m)
        \/ Acquire(t) \/ Unlock(t) \/ FailInTry(t) \/ FailOutsideTry(t) \/ RunExit(t)
    \/ \E w \in Workers : EnterTry(w) \/ LeaveTry(w) \/ WorkerDone(w) \/ ConsumeWorker(w)
    \/ ReaderDone \/ MainTake \/ MainClose \/ Ended

Fairness ==
    /\ \A t \in Threads : WF_vars(Unlock(t)) /\ SF_vars(RunExit(t)) /\ SF_vars(Acquire(t))
    /\ \A w \in Workers : SF_vars(LeaveTry(w)) /\ SF_vars(WorkerDone(w)) /\ SF_vars(ConsumeWorker(w))
    /\ SF_vars(ReaderDone) /\ SF_vars(MainTake) /\ SF_vars(MainClose)

Spec == Init /\ [][Next]_vars /\ Fairness

-----------------------------------------------------------------------------
(* A mutex is owned by at most the thread whose frames hold it. *)
LocksConsistent ==
    \A t \in Threads : holds[t] # None => owner[holds[t]] = t

(* After exit, every member on disk is complete. *)
NoPartialAfterExit == proc = "exit1" => (created \subseteq removed \/ completed)

(* Nothing is created after remove_partial ran. *)
NoCreateAfterCleanup == cleaned => created \subseteq removed \/ completed

(* bgen_files_complete before exit keeps the members. *)
CompletedSurvive == completed => removed = {}

(* A deferred error never lets the process exit 0. *)
ErrorNotLost == proc = "exit0" => \A t \in Threads : deferred[t] # "pending"

(* Once a thread calls util_exit outside util_try, the process ends. *)
Terminates == [](exiting => <>(proc = "exit1"))

(* No thread blocks on a mutex forever while the process lives. *)
NoLockDeadlock ==
    \A t \in Threads : [](pc[t] = "wait" => <>(pc[t] # "wait" \/ ~Live))

(* The reader's deferred error is raised, unless another exit beats it. *)
DeferredRaised ==
    deferred[Reader] = "pending" ~> (deferred[Reader] = "raised" \/ proc = "exit1")
=============================================================================
