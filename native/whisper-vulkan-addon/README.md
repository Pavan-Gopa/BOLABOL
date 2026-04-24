# Experimental Vulkan Whisper Addon (Intel macOS)

This addon enables Vulkan (MoltenVK) accelerated Whisper inference on Intel macOS machines with compatible AMD/Nvidia GPUs. It is optional. The existing `@kutalia/whisper-node-addon` continues to provide Metal on Apple Silicon and CPU fallback.

## Status
Early scaffold. You must manually supply `third_party/whisper.cpp` sources and have the LunarG Vulkan SDK installed.

## Prerequisites
1. Install Vulkan SDK (LunarG): https://vulkan.lunarg.com/
2. Export environment variable:
```bash
export VULKAN_SDK="/path/to/vulkansdk/macOS"
```
3. Add whisper.cpp sources:
```bash
mkdir -p native/whisper-vulkan-addon/third_party
cd native/whisper-vulkan-addon/third_party
git clone https://github.com/ggerganov/whisper.cpp.git --depth=1
```

## Build
From repo root:
```bash
npm run build:vulkan-addon
```
(or manually)
```bash
cd native/whisper-vulkan-addon
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --target whisper_vulkan_addon --config Release
```
Resulting addon: `native/whisper-vulkan-addon/build/Release/whisper_vulkan_addon.node`

## Runtime
The transcription worker attempts to load this addon first on `darwin x64`. If present, it sets engine = `vulkan`. Otherwise it falls back to `@kutalia/whisper-node-addon`.

## TODO
- Integrate dynamic model memory mapping parity with main addon
- Support streaming / partial segments
- Prebuild artifacts for CI distribution
- Add proper error codes & logging verbosity mapping

Use at your own risk while experimental.
