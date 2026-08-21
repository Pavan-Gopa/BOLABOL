# Attempt History

## DOC-01
- **Attempt 1 (workflow-coder)**: Failed due to runtime timeout (30 minutes).
  - **Approach**: Implemented document preflighting for DOCX/PDF/RTF/TXT/MD.
  - **Failure**: The RTF parser entered an infinite loop on complex fixture data. The agent attempted to rewrite the state machine with a linear walk but timed out before completing the replacement and verifying tests.
  - **Next Step**: Use a standard robust regex or third-party parser for RTF, or ensure the `parseRtf` loop has strict advancement guarantees (`pos` strictly increases).
- **Attempt 2 (workflow-coder + workflow-reviewer)**: Coder fixed RTF infinite loop (all tests pass). Reviewer requested changes.
  - **Reviewer Findings**: 
    1. Malformed PDF dict `<< /Type /Catalog /Pages [ >>` hangs in `parsePdfDict` due to missing EOF guard in array loop.
    2. PDF `FlateDecode` uses `inflateRawSync` but should use standard inflate, failing valid compressed PDFs.
    3. DOCX parser loses table/textbox metadata, emitting them as regular paragraphs.
    4. PDF block construction loses page index metadata despite plan requirements.
    5. PDF preflight checks size but fails to enforce 2000-page limit.
  - **Next Step**: Fix PDF and DOCX edge cases identified by Reviewer, add regression tests, and route back to Reviewer.
