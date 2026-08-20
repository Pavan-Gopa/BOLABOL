## Human Feedback (2026-08-20)
**Candidate S31D16TruthfulProgress2 Rejected**

1. **Progress bar missing (Stuck on "Starting..."):** Processing successfully finishes in ~5 minutes, but the UI shows an indeterminate spinner ("Starting...") for the entire duration. The UI must transition to a real determinate progress bar (showing chunks/percentage) during inference.
2. **Output Collision -> Overwrite:** The user explicitly requested to OVERWRITE existing companion text files instead of failing with an "Output conflict" error. The user shouldn't have to manually delete old files when retrying with a different model.
3. **Empty State "Start" Button:** The "Start" button can be clicked even when there are no folders added or no pending jobs. It must be disabled when there is no work to do.
4. **Auto-Stop on Completion:** When all jobs finish processing, the button stays on "Stop" and the green pulsing icon remains active. The system should automatically revert to the "Start" state (stop running) once the queue is complete.

Please fix these UI and logic issues so the batch processing feels polished and intuitive.
