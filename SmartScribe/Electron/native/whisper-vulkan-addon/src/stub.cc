#include <napi.h>

Napi::Object Init(Napi::Env env, Napi::Object exports) {
  Napi::Error::New(env, "Vulkan SDK not available. This is a stub addon; fallback to default whisper addon.").ThrowAsJavaScriptException();
  return exports;
}

NODE_API_MODULE(whisper_vulkan_addon, Init)
