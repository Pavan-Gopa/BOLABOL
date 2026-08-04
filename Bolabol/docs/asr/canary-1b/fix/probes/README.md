# S4b Probe Sources

The reproducible native probe source is
`docs/canary/harness/CanarySmdesaiSpike.swift`. It contains both the failing
smdesai Core ML frontend probe and the selected Path B native mel probe; it is
kept outside `Sources/` and has no external inference process.

Build it for the macOS 15 stateful Core ML API:

```bash
xcrun swiftc -O -parse-as-library -target arm64-apple-macosx15.0 \
  -o scratch/canary-1b-fix/bin/CanarySmdesaiSpike \
  docs/canary/harness/CanarySmdesaiSpike.swift
```

Run the EN short Path B probe:

```bash
scratch/canary-1b-fix/bin/CanarySmdesaiSpike \
  scratch/canary-spike/audio/en_short.wav \
  modelRoot=scratch/canary-1b-fix/smdesai \
  vocabPath=scratch/canary-spike/fi-models/vocab.json \
  frontend=native task=asr src=en tgt=en compute=cpu maxTokens=50
```

Run the AST probe:

```bash
scratch/canary-1b-fix/bin/CanarySmdesaiSpike \
  scratch/canary-spike/audio/en_short.wav \
  modelRoot=scratch/canary-1b-fix/smdesai \
  vocabPath=scratch/canary-spike/fi-models/vocab.json \
  frontend=native task=ast src=en tgt=fr compute=cpu maxTokens=50
```

The `vocab.json` argument is only for readable spike diagnostics. The hosted
package carries `canary_spe.model`; a later product adapter must use a native
SentencePiece implementation and must not add a Python runtime.
