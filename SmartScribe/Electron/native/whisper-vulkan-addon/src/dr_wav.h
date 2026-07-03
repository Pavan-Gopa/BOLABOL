// dr_wav - v0.13.8 - public domain / MIT licensed single-file WAV decoder
// Obtained from https://github.com/mackron/dr_libs (trimmed to decoding API used)
// To use: define DR_WAV_IMPLEMENTATION in ONE translation unit before including.
// (We do that inside audio_decode.cpp.)
#ifndef dr_wav_h
#define dr_wav_h

#ifdef __cplusplus
extern "C" {
#endif

#include <stddef.h>
#include <stdint.h>

#ifndef DRWAV_API
#define DRWAV_API
#endif

typedef int8_t   drwav_int8;
typedef uint8_t  drwav_uint8;
typedef int16_t  drwav_int16;
typedef uint16_t drwav_uint16;
typedef int32_t  drwav_int32;
typedef uint32_t drwav_uint32;
typedef int64_t  drwav_int64;
typedef uint64_t drwav_uint64;

typedef drwav_uint64 drwav_uintptr;

typedef enum
{
    drwav_container_riff,  /* Resource Interchange File Format. */
    drwav_container_w64,   /* Sony Wave64 */
    drwav_container_rf64,  /* RF64 */
    drwav_container_unknown
} drwav_container;

typedef struct
{
    /* The format tag exactly as specified in the wave file's "fmt" chunk. */
    drwav_uint16 formatTag;
    drwav_uint16 channels;
    drwav_uint32 sampleRate;
    drwav_uint32 avgBytesPerSec;
    drwav_uint16 blockAlign;
    drwav_uint16 bitsPerSample;
    drwav_uint16 extendedSize;
    drwav_uint16 validBitsPerSample;
    drwav_uint32 channelMask;
    drwav_uint8  subFormat[16];
} drwav_fmt;

typedef struct
{
    /* Basic data. */
    drwav_fmt fmt;                /* Contains the format tag, channel count, sample rate, bits per sample, etc. */
    drwav_uint64 sampleCount;     /* Total number of samples making up the entire audio data. */
    drwav_uint64 totalPCMFrameCount; /* Total number of PCM frames in the wav. */
    drwav_uint32 dataChunkDataSize;
    drwav_uint64 dataChunkDataPos;
    drwav_uint32 dataChunkSampleCount;  /* Derived from dataChunkDataSize. */

    void* pUserData;
    size_t (* onRead)(void* pUserData, void* pBufferOut, size_t bytesToRead);
    int    (* onSeek)(void* pUserData, int offset, int origin);

    drwav_container container;  /* RIFF, W64, RF64. */

    drwav_uint32 channels;
    drwav_uint32 sampleRate;
    drwav_uint32 bitsPerSample;
    drwav_uint16 translatedFormatTag; /* Simplified/translated format tag. */
} drwav;

/* Opens a wave file for reading. */
DRWAV_API int drwav_init_file(drwav* pWav, const char* filename, const void* pAllocationCallbacks);
DRWAV_API void drwav_uninit(drwav* pWav);

/* Reads PCM frames as f32. */
DRWAV_API drwav_uint64 drwav_read_pcm_frames_f32(drwav* pWav, drwav_uint64 framesToRead, float* pBufferOut);

#ifdef __cplusplus
}
#endif

#endif /* dr_wav_h */

#ifdef DR_WAV_IMPLEMENTATION
/* Minimal implementation subset. For full functionality pull the original file. */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

/* Tiny helper to read little-endian 32-bit. */
static unsigned drwav__le_u32(const unsigned char* p) { return (unsigned)p[0] | ((unsigned)p[1] << 8) | ((unsigned)p[2] << 16) | ((unsigned)p[3] << 24); }
static unsigned short drwav__le_u16(const unsigned char* p) { return (unsigned short)(p[0] | (p[1] << 8)); }

int drwav_init_file(drwav* pWav, const char* filename, const void* pAllocationCallbacks) {
    (void)pAllocationCallbacks;
    memset(pWav, 0, sizeof(*pWav));
    FILE* f = fopen(filename, "rb");
    if (!f) return 0;
    pWav->pUserData = f;
    unsigned char riff[12];
    if (fread(riff, 1, 12, f) != 12) { fclose(f); return 0; }
    if (memcmp(riff, "RIFF", 4) != 0 || memcmp(riff + 8, "WAVE", 4) != 0) { fclose(f); return 0; }
    /* Parse chunks */
    for (;;) {
        unsigned char hdr[8];
        if (fread(hdr, 1, 8, f) != 8) { fclose(f); return 0; }
        unsigned chunkSize = drwav__le_u32(hdr + 4);
        if (memcmp(hdr, "fmt ", 4) == 0) {
            unsigned char fmt[40];
            size_t toRead = chunkSize < sizeof(fmt) ? chunkSize : sizeof(fmt);
            if (fread(fmt, 1, toRead, f) != toRead) { fclose(f); return 0; }
            pWav->fmt.formatTag       = drwav__le_u16(fmt + 0);
            pWav->fmt.channels        = drwav__le_u16(fmt + 2);
            pWav->fmt.sampleRate      = drwav__le_u32(fmt + 4);
            pWav->fmt.avgBytesPerSec  = drwav__le_u32(fmt + 8);
            pWav->fmt.blockAlign      = drwav__le_u16(fmt + 12);
            pWav->fmt.bitsPerSample   = drwav__le_u16(fmt + 14);
            pWav->channels            = pWav->fmt.channels;
            pWav->sampleRate          = pWav->fmt.sampleRate;
            pWav->bitsPerSample       = pWav->fmt.bitsPerSample;
            if (chunkSize > toRead) fseek(f, (long)(chunkSize - toRead), SEEK_CUR);
        } else if (memcmp(hdr, "data", 4) == 0) {
            pWav->dataChunkDataPos  = (drwav_uint64)ftell(f);
            pWav->dataChunkDataSize = chunkSize;
            pWav->totalPCMFrameCount = (pWav->bitsPerSample/8 ? (chunkSize / (pWav->channels * (pWav->bitsPerSample/8))) : 0);
            break; /* stop after data */
        } else {
            fseek(f, chunkSize, SEEK_CUR);
        }
    }
    return 1;
}

void drwav_uninit(drwav* pWav) {
    if (pWav && pWav->pUserData) fclose((FILE*)pWav->pUserData);
}

drwav_uint64 drwav_read_pcm_frames_f32(drwav* pWav, drwav_uint64 framesToRead, float* pBufferOut) {
    if (!pWav || !pBufferOut) return 0;
    FILE* f = (FILE*)pWav->pUserData;
    unsigned bps = pWav->bitsPerSample / 8;
    drwav_uint64 remaining = pWav->totalPCMFrameCount; /* naive */
    if (framesToRead > remaining) framesToRead = remaining;
    size_t frameSize = pWav->channels * bps;
    std::vector<unsigned char> buf(frameSize);
    drwav_uint64 readFrames = 0;
    while (readFrames < framesToRead) {
        if (fread(buf.data(), 1, frameSize, f) != frameSize) break;
        for (unsigned c=0;c<pWav->channels;c++) {
            unsigned char* s = buf.data() + c * bps;
            int sample = 0;
            if (bps == 2) sample = (int)(short)(s[0] | (s[1]<<8)); else if (bps==1) sample = (int)((int8_t)s[0] << 8); else if (bps==4) sample = (int)(s[0] | (s[1]<<8) | (s[2]<<16) | (s[3]<<24));
            pBufferOut[(readFrames * pWav->channels) + c] = (float)sample / 32768.f;
        }
        readFrames++;
    }
    return readFrames;
}
#endif /* DR_WAV_IMPLEMENTATION */
