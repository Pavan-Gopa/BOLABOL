## Human Feedback (2026-08-20)
**Candidate S31.J1 Rejected**

1. **Folder addition visibility bug:** When a new folder is added in the UI, the files inside it are not visible in the middle column right away. The user has to toggle the "Watch this folder" switch off and then back on for the files to appear. They should populate immediately upon adding the folder.
2. **Processing freeze (hang at 0%):** When clicking "Start", the first file enters the "Processing" state but hangs indefinitely. There is zero visual progress (the progress bar doesn't move, and the status bar remains stuck). 
3. **Layout jump due to massive ID string:** Clicking "Start" causes the window to jump in height. This happens because the right column ("BatchJobDetailsView" -> "Configuration" -> "Provider") displays a massive, multi-line hex string (`batch-id-v2-000000...`), which is useless to the user and drastically breaks the layout.

Please fix these logic and UI issues so the folder populates immediately, processing actually runs and updates progress, and the massive ID is removed/hidden.
