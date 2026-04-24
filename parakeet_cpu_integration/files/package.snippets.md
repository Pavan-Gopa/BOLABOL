# Packaging notes (electron-builder)

Include the worker file and unpack ONNX native binaries.

```jsonc
{
  // ...
  "build": {
    // ...
    "files": [
      "dist/**/*",
      "main.js",
      "transcription.fork.js",
      "package.json"
    ],
    "asarUnpack": [
      "**/onnxruntime-node/**"
    ]
  }
}
```

- Worker caches models under `app.getPath('userData')/models` (portable across macOS/Windows/Linux).
- If you build multiple architectures, ensure `onnxruntime-node` has matching prebuilts; otherwise rebuild native modules per-target.
