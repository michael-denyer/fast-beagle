---------------------------- MODULE SlidingWindow ----------------------------
(***************************************************************************)
(* The read-ahead hand-over in src/vcf/sliding_window.c: hand_over,        *)
(* read_windows, read_ahead, sliding_window_next and sliding_window_close. *)
(* The reader thread produces windows 1..NWindows and then NULL (0 here),  *)
(* and hands each over through ahead and ready, waiting until the caller   *)
(* clears ready or sets stop. Producing window k with k in FailAt may      *)
(* instead fail (util_try catches util_exit): the reader sets error and    *)
(* ready and returns. The caller takes windows with sliding_window_next    *)
(* and may call sliding_window_close at any point, which sets stop and     *)
(* joins the reader. One mutex, held by lock, and one condition variable,  *)
(* changed, whose wait set is {reader, consumer} filtered on pc. A wait    *)
(* leaves the set only through a broadcast or a spurious wakeup, and the   *)
(* woken thread has to take the mutex again before it rereads the state,  *)
(* so a lost wakeup shows up as a deadlock or a stuck close.               *)
(***************************************************************************)
EXTENDS Integers, Sequences, FiniteSets

CONSTANTS NWindows, FailAt

ASSUME NWindows \in Nat \ {0} /\ FailAt \subseteq 1 .. NWindows

Null == 0
Windows == 1 .. NWindows

VARIABLES
    lock,      \* "none", "reader" or "consumer": who holds sw->mutex
    ready,     \* sw->ready
    stop,      \* sw->stop
    error,     \* sw->error != NULL
    ahead,     \* sw->ahead: Null or a window
    rpc,       \* the reader thread's program counter
    w,         \* the reader's local w in read_windows: Null or a window
    produced,  \* windows made so far (sw->window_index)
    failedAt,  \* the window whose production failed, or Null
    cpc,       \* the consumer's program counter
    got        \* what sliding_window_next returned, in order: windows or Null

vars == <<lock, ready, stop, error, ahead, rpc, w, produced, failedAt, cpc, got>>

ReaderPCs == {"produce", "h_lock", "h_set", "h_check", "h_wait", "h_relock", "e_lock", "e_set", "done"}
ConsumerPCs == {"idle", "n_lock", "n_check", "n_wait", "n_relock", "c_lock", "c_set", "c_join", "closed", "exited"}

Range(s) == {s[i] : i \in DOMAIN s}

TypeOK ==
    /\ lock \in {"none", "reader", "consumer"}
    /\ ready \in BOOLEAN
    /\ stop \in BOOLEAN
    /\ error \in BOOLEAN
    /\ ahead \in {Null} \cup Windows
    /\ rpc \in ReaderPCs
    /\ w \in {Null} \cup Windows
    /\ produced \in 0 .. NWindows
    /\ failedAt \in {Null} \cup Windows
    /\ cpc \in ConsumerPCs
    /\ got \in Seq({Null} \cup Windows) /\ Len(got) <= NWindows + 1
    /\ (lock = "reader") <=> (rpc \in {"h_set", "h_check", "e_set"})
    /\ (lock = "consumer") <=> (cpc \in {"n_check", "c_set"})

Init ==
    /\ lock = "none"
    /\ ready = FALSE
    /\ stop = FALSE
    /\ error = FALSE
    /\ ahead = Null
    /\ rpc = "produce"
    /\ w = Null
    /\ produced = 0
    /\ failedAt = Null
    /\ cpc = "idle"
    /\ got = <<>>

-----------------------------------------------------------------------------
(* Reader thread *)

(* read_windows line 403: next_*_window makes window produced + 1, or fails
   inside it, or w stays NULL once the last window has been read. *)
Produce ==
    /\ rpc = "produce"
    /\ IF produced = NWindows
         THEN /\ w' = Null
              /\ rpc' = "h_lock"
              /\ UNCHANGED <<produced, failedAt>>
         ELSE \/ /\ w' = produced + 1
                 /\ produced' = produced + 1
                 /\ rpc' = "h_lock"
                 /\ UNCHANGED failedAt
              \/ /\ produced + 1 \in FailAt
                 /\ failedAt' = produced + 1
                 /\ rpc' = "e_lock"
                 /\ UNCHANGED <<w, produced>>
    /\ UNCHANGED <<lock, ready, stop, error, ahead, cpc, got>>

(* hand_over line 382 *)
HandOverLock ==
    /\ rpc = "h_lock" /\ lock = "none"
    /\ lock' = "reader" /\ rpc' = "h_set"
    /\ UNCHANGED <<ready, stop, error, ahead, w, produced, failedAt, cpc, got>>

(* hand_over lines 383-385: publish w and broadcast. *)
HandOverSet ==
    /\ rpc = "h_set"
    /\ ahead' = w
    /\ ready' = TRUE
    /\ cpc' = IF cpc = "n_wait" THEN "n_relock" ELSE cpc
    /\ rpc' = "h_check"
    /\ UNCHANGED <<lock, stop, error, w, produced, failedAt, got>>

(* hand_over lines 386-389, then read_windows line 404. *)
HandOverCheck ==
    /\ rpc = "h_check"
    /\ IF ready /\ ~stop
         THEN /\ rpc' = "h_wait"
         ELSE /\ rpc' = IF stop \/ w = Null THEN "done" ELSE "produce"
    /\ lock' = "none"
    /\ UNCHANGED <<ready, stop, error, ahead, w, produced, failedAt, cpc, got>>

HandOverRelock ==
    /\ rpc = "h_relock" /\ lock = "none"
    /\ lock' = "reader" /\ rpc' = "h_check"
    /\ UNCHANGED <<ready, stop, error, ahead, w, produced, failedAt, cpc, got>>

(* read_ahead lines 417-423 *)
ErrorLock ==
    /\ rpc = "e_lock" /\ lock = "none"
    /\ lock' = "reader" /\ rpc' = "e_set"
    /\ UNCHANGED <<ready, stop, error, ahead, w, produced, failedAt, cpc, got>>

ErrorSet ==
    /\ rpc = "e_set"
    /\ error' = TRUE
    /\ ready' = TRUE
    /\ cpc' = IF cpc = "n_wait" THEN "n_relock" ELSE cpc
    /\ lock' = "none"
    /\ rpc' = "done"
    /\ UNCHANGED <<stop, ahead, w, produced, failedAt, got>>

(* pthread_cond_wait may return with no broadcast. *)
SpuriousReader ==
    /\ rpc = "h_wait"
    /\ rpc' = "h_relock"
    /\ UNCHANGED <<lock, ready, stop, error, ahead, w, produced, failedAt, cpc, got>>

-----------------------------------------------------------------------------
(* Consumer: the main thread *)

CallNext ==
    /\ cpc = "idle"
    /\ cpc' = "n_lock"
    /\ UNCHANGED <<lock, ready, stop, error, ahead, rpc, w, produced, failedAt, got>>

CallClose ==
    /\ cpc = "idle"
    /\ cpc' = "c_lock"
    /\ UNCHANGED <<lock, ready, stop, error, ahead, rpc, w, produced, failedAt, got>>

(* sliding_window_next line 427 *)
NextLock ==
    /\ cpc = "n_lock" /\ lock = "none"
    /\ lock' = "consumer" /\ cpc' = "n_check"
    /\ UNCHANGED <<ready, stop, error, ahead, rpc, w, produced, failedAt, got>>

NextRelock ==
    /\ cpc = "n_relock" /\ lock = "none"
    /\ lock' = "consumer" /\ cpc' = "n_check"
    /\ UNCHANGED <<ready, stop, error, ahead, rpc, w, produced, failedAt, got>>

(* sliding_window_next lines 428-438: wait, or exit on error, or take ahead
   (clearing ready and waking the reader), or return NULL leaving ready set.
   The caller may keep calling next after NULL and gets NULL each time; got
   records the first NULL only, which keeps the state space finite. *)
NextCheck ==
    /\ cpc = "n_check"
    /\ IF ~ready
         THEN /\ cpc' = "n_wait"
              /\ UNCHANGED <<ready, ahead, rpc, got>>
         ELSE IF error
         THEN /\ cpc' = "exited"
              /\ UNCHANGED <<ready, ahead, rpc, got>>
         ELSE IF ahead # Null
         THEN /\ got' = Append(got, ahead)
              /\ ahead' = Null
              /\ ready' = FALSE
              /\ rpc' = IF rpc = "h_wait" THEN "h_relock" ELSE rpc
              /\ cpc' = "idle"
         ELSE /\ got' = IF Null \in Range(got) THEN got ELSE Append(got, Null)
              /\ cpc' = "idle"
              /\ UNCHANGED <<ready, ahead, rpc>>
    /\ lock' = "none"
    /\ UNCHANGED <<stop, error, w, produced, failedAt>>

SpuriousConsumer ==
    /\ cpc = "n_wait"
    /\ cpc' = "n_relock"
    /\ UNCHANGED <<lock, ready, stop, error, ahead, rpc, w, produced, failedAt, got>>

(* sliding_window_close lines 462-466 *)
CloseLock ==
    /\ cpc = "c_lock" /\ lock = "none"
    /\ lock' = "consumer" /\ cpc' = "c_set"
    /\ UNCHANGED <<ready, stop, error, ahead, rpc, w, produced, failedAt, got>>

CloseSet ==
    /\ cpc = "c_set"
    /\ stop' = TRUE
    /\ rpc' = IF rpc = "h_wait" THEN "h_relock" ELSE rpc
    /\ lock' = "none"
    /\ cpc' = "c_join"
    /\ UNCHANGED <<ready, error, ahead, w, produced, failedAt, got>>

(* pthread_join returns once the reader thread has returned. *)
CloseJoin ==
    /\ cpc = "c_join" /\ rpc = "done"
    /\ cpc' = "closed"
    /\ UNCHANGED <<lock, ready, stop, error, ahead, rpc, w, produced, failedAt, got>>

Finished == cpc \in {"closed", "exited"} /\ UNCHANGED vars

Next ==
    \/ Produce \/ HandOverLock \/ HandOverSet \/ HandOverCheck \/ HandOverRelock
    \/ ErrorLock \/ ErrorSet \/ SpuriousReader
    \/ CallNext \/ CallClose \/ NextLock \/ NextRelock \/ NextCheck \/ SpuriousConsumer
    \/ CloseLock \/ CloseSet \/ CloseJoin
    \/ Finished

(* Every thread step runs when enabled, except the consumer's choice between
   next and close (left to the caller) and spurious wakeups. Taking the mutex
   is strongly fair: a thread that keeps waking spuriously and retaking the
   mutex does not starve the other thread of it forever. *)
Fairness ==
    /\ WF_vars(Produce) /\ WF_vars(HandOverSet) /\ WF_vars(HandOverCheck)
    /\ WF_vars(ErrorSet) /\ WF_vars(NextCheck) /\ WF_vars(CloseSet) /\ WF_vars(CloseJoin)
    /\ SF_vars(HandOverLock) /\ SF_vars(HandOverRelock) /\ SF_vars(ErrorLock)
    /\ SF_vars(NextLock) /\ SF_vars(NextRelock) /\ SF_vars(CloseLock)

Spec == Init /\ [][Next]_vars /\ Fairness

-----------------------------------------------------------------------------
(* The consumer receives windows 1, 2, 3, ... in order, none skipped or
   repeated, and NULL only after window NWindows. *)
InOrder ==
    \A i \in DOMAIN got : got[i] = i \/ (got[i] = Null /\ i > NWindows)

(* Once a window is in the consumer's hands, ahead never points at it, so
   sliding_window_close's window_free(sw->ahead) is never a double free. *)
AheadNotGiven == ahead # Null => ahead \notin Range(got)

(* After join, every window made is either with the consumer or in ahead,
   where close frees it. *)
NoLeak == cpc = "closed" => \A k \in 1 .. produced : k \in Range(got) \/ k = ahead

(* The reader fails producing window k+1 only after the consumer has taken
   windows 1..k, and the consumer takes nothing more once error is set
   (the comment at lines 408-412). *)
ErrorAfterPrefix == error => Len(got) = failedAt - 1 /\ Null \notin Range(got)

(* The reader never leaves a window behind when it fails. *)
ErrorNoAhead == error => ahead = Null

(* Liveness *)
CloseTerminates == [](cpc = "c_lock" => <>(cpc = "closed"))
NextReturns == [](cpc = "n_lock" => <>(cpc \in {"idle", "exited"}))
ExitOnlyOnError == [](cpc = "exited" => error /\ Len(got) = failedAt - 1)
=============================================================================
