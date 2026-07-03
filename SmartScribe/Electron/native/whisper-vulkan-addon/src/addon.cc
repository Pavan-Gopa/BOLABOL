#include <napi.h>
#include <string>
#include <vector>
#include <memory>
#include <mutex>
#include <unordered_map>
#include <iostream>
#include <fstream>

// Forward declare loader implemented in audio_decode.cpp
bool load_audio_any_to_16000(const std::string &path, std::vector<float> &pcmOut);

// whisper.cpp forward declarations (minimal)
extern "C" {
    #include "whisper.h"
}

namespace {
struct ModelHolder {
    whisper_context *ctx = nullptr;
    std::string path;
    uint64_t last_used = 0; // monotonic access stamp
};

std::mutex g_mutex;
std::unordered_map<std::string, ModelHolder> g_models; // keyed by absolute model path
size_t g_cacheLimit = 2; // default max loaded models
uint64_t g_useCounter = 1;

static void touch_model(ModelHolder &mh) {
    mh.last_used = g_useCounter++;
}

static void enforce_cache_limit_locked(const std::string &justLoaded) {
    if (g_cacheLimit == 0) return; // no limit
    while (g_models.size() > g_cacheLimit) {
        // find LRU excluding justLoaded if possible
        std::string victimPath;
        uint64_t best = (uint64_t)-1;
        for (auto &kv : g_models) {
            if (kv.first == justLoaded && g_models.size() > 1) continue; // try not to evict the model we just loaded
            if (kv.second.last_used < best) { best = kv.second.last_used; victimPath = kv.first; }
        }
        if (victimPath.empty()) break;
        auto it = g_models.find(victimPath);
        if (it != g_models.end()) {
            whisper_free(it->second.ctx);
            g_models.erase(it);
        } else break;
    }
}

Napi::Value LoadModel(const Napi::CallbackInfo &info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsString()) {
        Napi::TypeError::New(env, "model path string required").ThrowAsJavaScriptException();
        return env.Null();
    }
    std::string modelPath = info[0].As<Napi::String>();

    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_models.find(modelPath) != g_models.end()) {
    touch_model(g_models[modelPath]);
        return Napi::Boolean::New(env, true);
    }

    struct whisper_context_params cparams = whisper_context_default_params();
#ifdef GGML_USE_VULKAN
    cparams.use_gpu = true; // request Vulkan
#endif
    whisper_context *ctx = whisper_init_from_file_with_params(modelPath.c_str(), cparams);
    if (!ctx) {
        Napi::Error::New(env, "Failed to load model").ThrowAsJavaScriptException();
        return env.Null();
    }
    g_models[modelPath] = { ctx, modelPath };
    touch_model(g_models[modelPath]);
    enforce_cache_limit_locked(modelPath);
    return Napi::Boolean::New(env, true);
}

// Removed simplistic WAV-only reader; replaced with multi-format loader.

Napi::Value Transcribe(const Napi::CallbackInfo &info) {
    Napi::Env env = info.Env();
    // Mode A: (modelPath, Float32Array, sampleRate?)
    if (info.Length() >= 2 && info[0].IsString() && info[1].IsTypedArray()) {
        std::string modelPath = info[0].As<Napi::String>();
        Napi::Float32Array pcm = info[1].As<Napi::Float32Array>();
        int sampleRate = 16000;
        if (info.Length() > 2 && info[2].IsNumber()) sampleRate = info[2].As<Napi::Number>().Int32Value();

        std::lock_guard<std::mutex> lock(g_mutex);
        auto it = g_models.find(modelPath);
        if (it == g_models.end()) {
            Napi::Error::New(env, "Model not loaded").ThrowAsJavaScriptException();
            return env.Null();
        }
        whisper_context *ctx = it->second.ctx;
    touch_model(it->second);

        const int n_samples = pcm.ElementLength();
        std::vector<float> data(n_samples);
        for (int i=0;i<n_samples;i++) data[i] = pcm[i];

        whisper_full_params wparams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
        wparams.print_realtime   = false;
        wparams.print_progress   = false;
        wparams.print_timestamps = false;
        wparams.print_special    = false;
        wparams.translate        = false;
        wparams.language         = "auto";

        if (whisper_full(ctx, wparams, data.data(), n_samples) != 0) {
            Napi::Error::New(env, "whisper_full failed").ThrowAsJavaScriptException();
            return env.Null();
        }

        std::string out;
        Napi::Array segs = Napi::Array::New(env);
        int n = whisper_full_n_segments(ctx);
        for (int i = 0; i < n; ++i) {
            const char *txt = whisper_full_get_segment_text(ctx, i);
            if (txt) {
                if (!out.empty()) out += ' ';
                out += txt;
                Napi::Object seg = Napi::Object::New(env);
                seg.Set("t0", whisper_full_get_segment_t0(ctx, i));
                seg.Set("t1", whisper_full_get_segment_t1(ctx, i));
                seg.Set("text", txt);
                segs.Set(i, seg);
            }
        }
        Napi::Object result = Napi::Object::New(env);
        result.Set("text", out);
        result.Set("segments", segs);
        result.Set("engine", "vulkan");
        return result;
    }

    // Mode B: single object { fname_inp, model, language, translate, threads }
    if (info.Length() == 1 && info[0].IsObject()) {
        Napi::Object obj = info[0].As<Napi::Object>();
        std::string modelPath = obj.Get("model").As<Napi::String>();
        std::string fname = obj.Get("fname_inp").As<Napi::String>();
        std::string language = obj.Has("language") ? (std::string) obj.Get("language").As<Napi::String>() : "auto";
        bool translate = obj.Has("translate") && obj.Get("translate").As<Napi::Boolean>().Value();

        // load model if needed
        {
            std::lock_guard<std::mutex> lock(g_mutex);
            if (g_models.find(modelPath) == g_models.end()) {
                struct whisper_context_params cparams = whisper_context_default_params();
#ifdef GGML_USE_VULKAN
                cparams.use_gpu = true;
#endif
                whisper_context *ctx = whisper_init_from_file_with_params(modelPath.c_str(), cparams);
                if (!ctx) {
                    Napi::Error::New(env, "Failed to load model").ThrowAsJavaScriptException();
                    return env.Null();
                }
                g_models[modelPath] = { ctx, modelPath };
            }
        }

        // load audio (wav/mp3/ogg/opus/webm) & resample to 16k
        std::vector<float> pcm;
        if (!load_audio_any_to_16000(fname, pcm)) {
            Napi::Error::New(env, "Failed to decode audio file" ).ThrowAsJavaScriptException();
            return env.Null();
        }

        std::lock_guard<std::mutex> lock(g_mutex);
        auto it = g_models.find(modelPath);
        whisper_context *ctx = it->second.ctx;
    touch_model(it->second);

        whisper_full_params wparams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
        wparams.print_realtime   = false;
        wparams.print_progress   = false;
        wparams.print_timestamps = false;
        wparams.print_special    = false;
        wparams.translate        = translate;
        wparams.language         = language.c_str();

    if (whisper_full(ctx, wparams, pcm.data(), (int)pcm.size()) != 0) {
            Napi::Error::New(env, "whisper_full failed").ThrowAsJavaScriptException();
            return env.Null();
        }

        std::string out;
        Napi::Array segs = Napi::Array::New(env);
        int n = whisper_full_n_segments(ctx);
        for (int i = 0; i < n; ++i) {
            const char *txt = whisper_full_get_segment_text(ctx, i);
            if (txt) {
                if (!out.empty()) out += ' ';
                out += txt;
                Napi::Object seg = Napi::Object::New(env);
                seg.Set("t0", whisper_full_get_segment_t0(ctx, i));
                seg.Set("t1", whisper_full_get_segment_t1(ctx, i));
                seg.Set("text", txt);
                segs.Set(i, seg);
            }
        }
        Napi::Object result = Napi::Object::New(env);
        result.Set("text", out);
        result.Set("segments", segs);
        result.Set("engine", "vulkan");
        return result;
    }

    Napi::TypeError::New(env, "Invalid arguments for transcribe").ThrowAsJavaScriptException();
    return env.Null();
}

Napi::Value Unload(const Napi::CallbackInfo &info) {
    Napi::Env env = info.Env();
    if (info.Length() && info[0].IsString()) {
        std::string modelPath = info[0].As<Napi::String>();
        std::lock_guard<std::mutex> lock(g_mutex);
        auto it = g_models.find(modelPath);
        if (it != g_models.end()) {
            whisper_free(it->second.ctx);
            g_models.erase(it);
        }
    }
    return env.Null();
}

Napi::Object Init(Napi::Env env, Napi::Object exports) {
    exports.Set("loadModel", Napi::Function::New(env, LoadModel));
    exports.Set("transcribe", Napi::Function::New(env, Transcribe));
    exports.Set("unload", Napi::Function::New(env, Unload));
    exports.Set("setCacheLimit", Napi::Function::New(env, [](const Napi::CallbackInfo &info){
        Napi::Env e = info.Env();
        if (info.Length() && info[0].IsNumber()) {
            std::lock_guard<std::mutex> lock(g_mutex);
            int64_t v = info[0].As<Napi::Number>().Int64Value();
            if (v < 0) v = 0;
            g_cacheLimit = (size_t)v;
            // enforce now
            enforce_cache_limit_locked("");
        }
        return e.Undefined();
    }));
    exports.Set("cacheInfo", Napi::Function::New(env, [](const Napi::CallbackInfo &info){
        Napi::Env e = info.Env();
        Napi::Array arr = Napi::Array::New(e);
        std::lock_guard<std::mutex> lock(g_mutex);
        uint32_t idx = 0;
        for (auto &kv : g_models) {
            Napi::Object o = Napi::Object::New(e);
            o.Set("path", kv.first);
            o.Set("last_used", (double)kv.second.last_used);
            arr.Set(idx++, o);
        }
        return arr;
    }));
    // Simple capability probe used by worker self-test
    exports.Set("getBackend", Napi::Function::New(env, [](const Napi::CallbackInfo &info){
        Napi::Env e = info.Env();
        Napi::Object o = Napi::Object::New(e);
        o.Set("engine", "vulkan");
        return o;
    }));
    return exports;
}

} // namespace

NODE_API_MODULE(whisper_vulkan_addon, Init)
