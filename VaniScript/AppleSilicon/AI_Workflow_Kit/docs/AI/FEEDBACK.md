## Human Feedback (2026-08-20)
**Candidate S31D16TruthfulProgress3 Rejected**

Human confirmed exactly one requested behavior works: existing companion `.txt`
files are overwritten automatically. Preserve that behavior.

Still broken:
1. **No real per-file progress:** the active row and detail pane remain on the
   indeterminate `Starting…` spinner for the whole transcription. Replace every
   processing spinner with a horizontal progress bar owned by that file row.
   WhisperKit audio-position callbacks must persist increasing fractions so the
   bar visibly advances during a long file.
2. **No automatic completion:** after all files are completed and their `.txt`
   companions exist, the Batch run remains active and the primary button still
   says `Stop`. A drained queue must tear down the watcher/run and return the
   primary action to `Start`.
3. **Stop is not trustworthy:** the explicit `Stop` action must end the active
   run and leave no green running indicator or phantom processing state.

Do not report completion from unit assertions alone. The replacement candidate
must demonstrate monotonic persisted progress for one file and a real run-state
transition to stopped after the final completed job.

## Human Feedback (2026-08-20, Candidate 4)
**Candidate S31D16PerFileProgress4 Rejected**

Human runtime evidence supersedes the earlier request for determinate bars:

1. **The value bar is still disconnected from useful runtime feedback.** It
   remains visually fixed on the first processing file for minutes while the
   three-file queue completes. Remove processing value bars from both the job
   row and detail pane.
2. **Show sequential ownership instead.** Exactly the active file row uses a
   compact native spinner and `Processing…`; pending rows retain their clock;
   each finished row becomes a green checkmark with `Completed`. When the
   coordinator advances, the spinner must visibly move to the next row.
3. **Keep row geometry stable.** A pending, processing, or completed transition
   must not add a second progress row or change the list-row height.
4. **Stop vertical window jumps.** The Batch sheet must keep a stable explicit
   size when Start is pressed and when job details/status content changes.

Preserve automatic same-stem `.txt` replacement, sequential execution,
Start/Stop behavior, provider configuration, errors, accessibility, and the
three-column layout. This is a bounded presentation-layer repair; do not change
the transcription pipeline or fabricate percentage progress.

## Human Feedback (2026-08-20, Candidate 5)
**Candidate S31D17SequentialState5 Rejected**

The new icons render, and the Batch sheet no longer appears to resize in the
supplied before/after screenshots. The remaining failure is spatial continuity:
the spinner appears to stay in the first visible row for the whole Batch run,
then all rows become completed together from the Human's perspective.

Screenshot evidence exposes the root presentation defect. The processing
screenshot has the interview file in row 1. The completed screenshot orders the
37-second file first, the 1m15s file second, and the 2m49s interview last.
`BatchTranscriptionStore.refreshJobs()` sorts every refresh by descending
`updatedAt`, while the repository and `claimNext` use ascending
`created_at, id`. Every state update therefore reorders the list and pulls the
new active job back to the top, making the spinner look stationary.

Preserve repository queue order in the UI. Rows must remain in their original
positions for the whole run: row 1 spins then becomes a green check, the spinner
moves to row 2, then row 3. Do not change ASR execution, durations, automatic
companion replacement, explicit/final Stop behavior, fixed sheet dimensions, or
the spinner/checkmark design.

## Human Feedback (2026-08-20, Candidate 6)
**Candidate S31D18StableQueueOrder6 Rejected**

The stable repository order did not produce the required live presentation in
the packaged app. Human runtime evidence remains unchanged: during a three-file
run, only one row visibly owns the spinner for the entire wait; the Human sees
the other files become completed only at the end. The candidate therefore still
reads as one opaque batch operation, not three sequential per-file operations.

Required observable behavior remains exact: all queued rows stay visible; row 1
shows the only spinner while processing; immediately after its repository state
becomes completed, row 1 shows a green check and row 2 shows the spinner; then
the same handoff occurs from row 2 to row 3. Each transition must reach the live
SwiftUI list while processing continues, not merely exist in repository/store
snapshots or unit assertions. Preserve sequential ASR, fixed sheet geometry,
automatic same-stem companion replacement, and the existing compact visual
language.

## Human Feedback (2026-08-20, Candidate 7)
**Candidate S31D20AwaitedHandoff7 Rejected**

Human runtime evidence again shows one stale spinner for the whole three-file
run and all green checks only at the end. Main then inspected the exact running
binary and live state rather than relying on unit tests:

- PID 11982 is the freshly built
  `dist/VaniScript.app/Contents/MacOS/VaniScript`.
- While its accessibility tree still showed the first file as `Processing` and
  the other two as `Pending`, live `jobs.sqlite` already held the first file as
  `completed`, the second as `processing`, and the third as `pending`.
- The app-level `RuntimeBridge` in `makeBatchStore` is a local object. Both the
  coordinator and watcher closures capture it weakly, and `RuntimeBridge.store`
  is also weak. No strong owner survives `makeBatchStore`, so the bridge is
  deallocated and real processing/reconciliation callbacks become no-ops.
- Tests retained their separate bridge strongly for the test scope, so they
  could not expose this packaged-app lifetime defect.

Required repair: keep the app bridge alive without creating a store cycle, then
prove the real app receives each processing callback. Reviewer must judge this
exact lifetime path and the requested visible per-file handoff. Tester remains
explicitly skipped by Human.

## Human Feedback (2026-08-20, Candidate 8)
**Live handoff accepted; Batch control/presentation refinement requested**

Human confirms the sequential behavior is now essentially correct: completed
files retain green checks and one active spinner advances through the queue.
Candidate 8 remains the behavioral baseline.

Requested bounded refinement:

1. Move active file time, chunk count, and percentage out of the global header
   and into that file's own row, beside or immediately below its filename.
2. Add the three shared audio-chunking settings directly to Batch configuration:
   Chunk Duration (minutes), Silence Threshold (dB), and Minimum Silence (ms).
   These edit the same `AppSettings` values as Settings > Chunking.
3. Do not duplicate Slice Mode in Batch. Batch uses the silence controls; the
   Human does not need the Fixed/Silence selector here.
4. Keep configuration hierarchy coherent: provider/model, the three chunking
   controls, then Require canonical names and its explanatory text.
5. Make the primary action unmistakable: Start uses a play symbol and green
   prominent treatment when enabled; Stop uses a stop symbol and red prominent
   treatment while running; disabled state remains visibly disabled.
6. Preserve the now-working callback lifetime, sequential execution, fixed
   rows/window, companion semantics, and accessibility.

## Human Feedback (2026-08-20, Candidate 9)
**Long Gemini Batch jobs finish all chunks but fail before companion writing**

Human processed two approximately one-hour lectures with 11 chunks each.
Every cloud chunk completed, but no `.txt` companion was written. Both rows
ended Failed with `The transcription produced invalid timed text`.

Main reproduced the persisted failure from the real Batch SQLite records:

- both jobs have `progress = 1`, `total_chunks = 11`, and all 11 checkpoint
  payloads preserved (approximately 84–85 KiB each);
- failures contain only `nonMonotonic(cueIndex:)` violations;
- Gemini returned noisy point timestamps: some cue starts exceeded their
  five-minute chunk, some equal starts caused the prior synthesized cue to end
  at the whole chunk boundary, and one checkpoint retained relative 295–345
  second timestamps instead of receiving its absolute file offset;
- `SessionState.reconstructCuesFromTimestampedText` converts a non-increasing
  next marker to `max(current + 1, chunkEnd)`, creating a long end time that
  decreases at the following cue; its all-or-nothing relative-offset heuristic
  also rejects an otherwise-relative marker list when one model timestamp
  exceeds the chunk duration tolerance;
- `BatchTranscriptionCoordinator` then flattens the saved cues and rejects them
  before `AtomicCompanionWriter.write`, so completed transcription text is
  stranded even though no provider work remains.

Required repair:

1. Normalize cloud marker timestamps within each planned chunk while preserving
   response text order and bounding every cue to that chunk.
2. Recover already persisted all-chunk checkpoints without another cloud call:
   if resumed checkpoint cues violate their planned chunk timeline, rebuild only
   those checkpoint cues from the preserved checkpoint text and exact planned
   chunk bounds, persist the repaired checkpoints, then finalize normally.
3. Keep strict rejection for non-timeline corruption (non-finite/negative
   duration, empty text) and preserve atomic companion/output-collision safety.
4. Prove the two observed failure shapes: oversized/equal provider timestamps
   and an all-11-checkpoint resume must produce a complete companion with zero
   provider calls.

### Candidate 10 recovery evidence

- Fresh primary Reviewer approved S31.D23 with
  `human_request_correspondence: yes`.
- Main passed 23 `ProjectArchiveTests` and 22
  `NativeProcessingPipelineASRTests`; the all-complete 11-checkpoint fixture
  proves zero cloud calls.
- Before touching live storage, Main saved the real Batch SQLite database/WAL
  under `.omp/runtime-fixtures/S31D23-live-recovery-backup/`.
- Main restored the two preserved original all-11-checkpoint payloads to the
  current jobs and launched the reviewed packaged candidate.
- Both real jobs completed from saved checkpoints. No timed-text error remains.
- Companions now exist beside the source files:
  - `2015-10-23_KKS_SB_10-69-40_Special-Mercy-Of-Krishna.txt`
    — 1,179 lines / 47,686 bytes;
  - `2021-10-09_KKS_SB_3-4-16_New-York_us.txt`
    — 855 lines / 40,754 bytes.
- SQLite records are `completed`, `progress = 1`, `total_chunks = 11`,
  `last_error = NULL`, with non-null output fingerprints.
