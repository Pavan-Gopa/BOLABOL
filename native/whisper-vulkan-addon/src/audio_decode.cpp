// Unified multi-format decoder using miniaudio (bundled in whisper.cpp examples)
// Supports: WAV, MP3, FLAC, OGG/Vorbis, AAC (via CoreAudio on macOS), etc.
// Output: mono float32 16 kHz

#include <vector>
#include <string>
#include <cstring>
#include <cctype>
#include <algorithm>

#ifndef MINIAUDIO_IMPLEMENTATION
 #define MINIAUDIO_IMPLEMENTATION
#endif
#define MA_NO_ENCODING
#define MA_NO_GENERATION
#include "miniaudio.h"

static inline std::string lower(const std::string &s) {
    std::string r=s; std::transform(r.begin(), r.end(), r.begin(), [](unsigned char c){ return std::tolower(c); }); return r;
}

// Decode any supported format to mono float32 using miniaudio
static bool decode_any(const std::string &path, std::vector<float> &out, int &sr) {
    ma_decoder_config cfg = ma_decoder_config_init(ma_format_f32, 0, 0); // output native channels (we'll mix down)
    ma_decoder dec;
    if (ma_decoder_init_file(path.c_str(), &cfg, &dec) != MA_SUCCESS) return false;
    sr = dec.outputSampleRate;
    const int channels = dec.outputChannels;
    ma_uint64 totalFrames = 0;
    if (ma_decoder_get_length_in_pcm_frames(&dec, &totalFrames) != MA_SUCCESS || totalFrames == 0) {
        // Fallback: stream read
        totalFrames = 0; // unknown
    }
    std::vector<float> tmpInterleaved;
    if (totalFrames > 0) tmpInterleaved.resize((size_t)totalFrames * channels);
    ma_uint64 framesReadTotal = 0;
    const ma_uint64 kChunk = 8192;
    if (totalFrames == 0) {
        std::vector<float> chunk(kChunk * channels);
        while (true) {
            ma_uint64 got = 0;
            if (ma_decoder_read_pcm_frames(&dec, chunk.data(), kChunk, &got) != MA_SUCCESS || got == 0) break;
            tmpInterleaved.insert(tmpInterleaved.end(), chunk.begin(), chunk.begin() + (size_t)got * channels);
            framesReadTotal += got;
        }
    } else {
        ma_uint64 remaining = totalFrames;
        ma_uint64 offsetFrames = 0;
        while (remaining > 0) {
            ma_uint64 toRead = remaining > kChunk ? kChunk : remaining;
            ma_uint64 got = 0;
            if (ma_decoder_read_pcm_frames(&dec, tmpInterleaved.data() + offsetFrames * channels, toRead, &got) != MA_SUCCESS || got == 0) break;
            remaining -= got;
            offsetFrames += got;
            framesReadTotal += got;
        }
        tmpInterleaved.resize((size_t)framesReadTotal * channels);
    }
    ma_decoder_uninit(&dec);
    if (framesReadTotal == 0 || tmpInterleaved.empty()) return false;
    // Mixdown
    out.resize((size_t)framesReadTotal);
    if (channels == 1) {
        std::copy(tmpInterleaved.begin(), tmpInterleaved.end(), out.begin());
    } else {
        for (ma_uint64 f = 0; f < framesReadTotal; ++f) {
            double acc = 0.0;
            for (int c = 0; c < channels; ++c) acc += tmpInterleaved[(size_t)f * channels + c];
            out[(size_t)f] = (float)(acc / channels);
        }
    }
    return true;
}

static void resample_linear(const std::vector<float> &in, int srIn, std::vector<float> &out, int srOut) {
    if (srIn == srOut) { out = in; return; }
    double ratio = (double)srOut / (double)srIn;
    size_t nOut = (size_t)(in.size() * ratio);
    out.resize(nOut);
    for (size_t i=0;i<nOut;i++) {
        double x = (double)i / ratio;
        size_t i0 = (size_t)x;
        size_t i1 = std::min(i0+1, in.size()-1);
        double t = x - i0;
        out[i] = (float)((1.0 - t)*in[i0] + t*in[i1]);
    }
}

bool load_audio_any_to_16000(const std::string &path, std::vector<float> &pcmOut) {
    std::vector<float> pcm; int sr = 0; if (!decode_any(path, pcm, sr)) return false;
    if (sr != 16000) { std::vector<float> rs; resample_linear(pcm, sr, rs, 16000); pcmOut.swap(rs); }
    else pcmOut.swap(pcm);
    return true;
}
