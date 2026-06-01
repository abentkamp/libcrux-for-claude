# Resume prompt — paste into a fresh session

Wrote 2026-05-08 evening.  Resumes after commit `03501b021` ("ml-dsa:
trait-surface cleanup + AVX2 Track B + perf experiments").  Branch:
`ml-dsa-proofs`.  Repo: `/Users/karthik/libcrux-ml-dsa-proofs/libcrux-ml-dsa`.

---

```
You're resuming an ML-DSA F*/hax verification project after a long
working session that closed with commit 03501b021.

Repo: /Users/karthik/libcrux-ml-dsa-proofs/libcrux-ml-dsa
Branch: ml-dsa-proofs
HEAD at session start: 03501b021 (verify this — see Step 1)

## Step 1 — load context

Load the libcrux F* skill (the playbook for this codebase):
    /skill fstar-for-libcrux

Confirm HEAD and tree state:
    cd /Users/karthik/libcrux-ml-dsa-proofs/libcrux-ml-dsa
    git log -3 ml-dsa-proofs
    # expected top: 03501b021 ml-dsa: trait-surface cleanup + AVX2 Track B + perf experiments
    git diff
    # expected: empty (tree was clean at commit time)

Then read these files in order — they cumulatively give you the
project state:

1. proofs/agent-status/session-state-2026-05-08-evening.md
   — handoff doc.  All wins kept, reverts, open items, working
   tree state at session end.

2. proofs/agent-status/abstraction-boundary-audit-2026-05-07.md
   — TL;DR + Phase E (risk register + remediation roadmap).

3. proofs/agent-status/fstar-perf-top20.md
   — most recent 2-3 snapshots.  2026-05-08b is the perf baseline
   to beat (bare-forall + --split_queries always — measured 11.8s
   on Avx2.impl_1, 0.52s on Portable.impl_1).
   Note: 03501b021 traded perf for forall8/32 abstraction uniformity;
   the post-commit shape is forallN macros + monolithic VC + rlimit
   200 (Portable) / 400 (Avx2).  Slower (~6× on impl_1 hotspots) but
   abstraction-uniform.

4. proofs/agent-status/hint-deletion-experiment-2026-05-08.md
   — Cross-cut summary section.  3 hard-fail-without-hints functions
   identified.

5. proofs/agent-status/qi-baseline-2026-05-08.md
   — qi.profile baseline of 6 hot/borderline queries.  Note that
   the baseline pre-dated the AVX2 Track B refactor; Avx2.impl_1's
   query structure has since changed.

## Step 2 — confirm baseline

    JOBS=4 ./hax.sh prove > /tmp/resume-baseline.log 2>&1
    grep -cE '^\* Error' /tmp/resume-baseline.log    # should be 0
    grep -c 'Verified module' /tmp/resume-baseline.log    # should be 99

If the baseline doesn't pass, something has drifted (e.g., other
worktrees changed shared deps, hax-lib version churn).  Diagnose
before any new edits.

## Step 3 — MANDATORY profile-before-fix discipline

Before applying ANY structural fix to a slow/failing F* proof, you MUST:

1. Run the prove with --query_stats (default in this build) to
   identify the slow function/query.
2. For the slowest target query, dump the .smt2 by re-checking
   the affected module with --log_queries:
       cd proofs/fstar/extraction
       OTHERFLAGS='--log_queries --z3refresh' make -k check/<Module>.fst > /tmp/foo.log 2>&1
3. Run smt.qi.profile=true on the dumped .smt2 to identify the
   dominant quantifier:
       timeout 200 z3-4.13.3 smt.qi.profile=true smt.qi.profile_freq=20000 \
           queries-<Module>-<N>.smt2 > /tmp/q.txt 2> /tmp/qi.txt
       awk -F: '/^\[quantifier_instances\]/ {n=$1; sub(/^\[quantifier_instances\] /, "", n);
                gsub(/[[:space:]]+$/, "", n); count=$2+0; printf "%10d %s\n", count, n}' \
           /tmp/qi.txt | sort -rn | head -15

The dominant quantifier (named or `k!N` anonymous) tells you WHAT
to fix.  Without this, you're guessing.

Memory rule `feedback_smtprofile_before_negative` is mandatory:
"agents may NOT report cliff/blocker/partial without first running
smtprofiling on the failing query".

In the prior session we burned cycles testing the audit's k!63-cascade
hypothesis (mont_mul clause drop) which gave only a 16% reduction —
the cliff turned out to be a different mechanism (monolithic VC,
fixed by --split_queries always with no opacity changes).  Profile
before refactoring.

ALSO: don't trust stale background logs.  Rerun the prove if the log
is more than ~15 min old or if other worktrees were doing fstar work
concurrently.  We were burned by this once in the prior session.

ALSO: when comparing perf across iterations, do a cold-cache full prove
for apples-to-apples timings:
    rm -f /Users/karthik/libcrux-ml-dsa-proofs/.fstar-cache/checked/Libcrux_ml_dsa.*.fst.checked
    JOBS=4 ./hax.sh prove > ...
For just verifying clean after a small edit, targeted clearing of
only the modules whose Rust source you changed is enough — make
handles staleness incrementally.

## Step 4 — pick next priority

Tier 1 (post-experiment, not in original audit):

  a) Un-admit Ml_dsa_generic::generate_key_pair body and re-prove.
     The body has been admitted since the prior session.  Site:
     src/ml_dsa_generic.rs around line 91-100 (search for the
     2026-05-08 follow-up comment + `hax_lib::fstar!("admit ()")`).
     If q60 still cliffs, profile q60 first (per the recipe in
     Step 3), THEN decide on opacity work (audit items 25-27).
     Do NOT preemptively apply the trait poly-forall opacity refactor
     without seeing the qi.profile.

  b) 3 hard-fail-without-hints functions:
     - Simd.Portable.Encoding.Gamma1::deserialize_when_gamma1_is_2_pow_17_
     - Matrix::compute_matrix_x_mask
     - Simd.Portable.Encoding.T0::deserialize
     For each: profile first, then factor lemmas / shrink per-conjunct
     queries based on the profile.  All three already have
     --split_queries always; their problem is per-conjunct rlimit-sat
     without hint guidance.

Tier 2 (audit cleanup — abstraction wins, may not be perf wins):

  c) rejection_sample_* posts in src/simd/traits.rs (3 sites near
     lines 192, 204, 213) — bare `forall (i:nat{i < Seq.length
     out_future}). i < v $result ==> ...`.  Variable-length slice
     prefix, can't use forall8/32.  Audit items 13-15: introduce
     `rejection_sample_count_post (out: t_Slice i32) (count: usize)
     (lo hi: i32) : prop` opaque pred.

  d) reduce_lane_post / montgomery_multiply_lane_post /
     shift_left_then_reduce_lane_post raw `%`/`*` in bodies
     (audit items 4, 8, 9).  Introduce `mod_q_eq` opaque pred per
     trait-correctness-post-design-draft.md.  Lookup lemmas have NO
     SMTPats and only 2 callers (impl bodies), so leak risk is
     currently zero — pure abstraction tier.

Tier 3 (perf optimization):

  e) Consider reverting state (d′) to state (a) (bare-forall +
     --split_queries always) IF the trait-uniformity isn't worth
     the ~6× perf cost on impl_1 hotspots.  Specifically, this would
     mean: revert the Spec.Utils.forallN macros in trait pre/post +
     impl posts back to bare `forall (i:nat). i < N ==> P i`, AND
     restore `--split_queries always` on the impl blocks +
     reduce_with_proof.  Measured impact:
       (a) Avx2.impl_1 11.8s, Portable 0.52s, reduce_with_proof 1.7s
       (d′) Avx2.impl_1 50.9s, Portable 14.5s, reduce_with_proof 19.9s
     The +~80s wall on cold prove is the cost of forallN uniformity.

## Step 5 — operational rules

Memory rules that apply (auto-loaded; reproduced for emphasis):

- NEVER bulk-delete F* .checked files.  hax.py prove / make handle
  staleness incrementally.  Targeted single-file rm is OK if you know
  what you're invalidating.
- NEVER manually edit extracted Hacspec_* F* files.
- ALWAYS redirect make/prove output to /tmp/<name>.log + grep for errors.
  Don't Read full logs into context.
- ALWAYS use `cd ... && cmd` within ONE Bash call (cwd resets between calls).
- CAP concurrent fstar processes at JOBS=4 (other worktrees may be
  running fstar; saturating beyond 4 stalls everyone).
- ALWAYS run ./hax.sh extract after Rust source edits, before make.
- Per-method debug budget: 30-60 min.  If a method exceeds, document
  the blocker in proofs/agent-status/<name>-status.md and move on.
- DO NOT bump --z3rlimit to "fix" failing proofs.  Profile first.
  Hard cap is 800 (400 with --split_queries).  EXCEPTION: when forallN
  macros are used in trait pre/post, the unfolded N-way conjunction
  legitimately needs proportionally more rlimit budget — this is
  resource scaling, not a band-aid.  rlimit 200/400 on impl blocks
  with forallN is appropriate (see commit 03501b021).
- forall8/forall32 macros (transparent N-way conjunction) DO NOT
  compose with --split_queries always.  Choose one per scope:
  bare-forall + split_queries OR forallN + monolithic + bumped rlimit.
  See session-state doc for measured evidence.

## Default mode

Auto mode by default.  Make reasonable assumptions, prefer action over
planning.  Ask only when a decision has real reversibility/blast-radius
(commits, force-pushes, large structural refactors that may regress).

## "Done" criterion

Per proofs/agent-status/sprint-plan-2026-05-03.md Sprint A success
criterion:
- 0 F* errors on JOBS=4 ./hax.sh prove
- cargo test --release --lib 20/20
- Body admits in keygen/sign/verify cone reduced (currently:
  generate_key_pair admit re-added in 03501b021 as a tactical move;
  un-admitting is Tier 1 priority a).

Pick one Tier 1 or Tier 2 item, profile if applicable, work it
through, measure, document.  Save status reports in
proofs/agent-status/.
```
