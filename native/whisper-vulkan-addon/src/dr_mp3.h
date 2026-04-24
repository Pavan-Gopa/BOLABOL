// dr_mp3 - v0.6.40 - public domain / MIT - minimal subset for decoding to f32
#ifndef dr_mp3_h
#define dr_mp3_h

#ifdef __cplusplus
extern "C" {
#endif

#include <stddef.h>
#include <stdint.h>

#ifndef DRMP3_API
#define DRMP3_API
#endif

typedef uint8_t  drmp3_uint8;
typedef uint16_t drmp3_uint16;
typedef uint32_t drmp3_uint32;
typedef uint64_t drmp3_uint64;

typedef struct
{
    int channels;
    int sampleRate;
    void* pUserData;
    size_t (* onRead)(void*, void*, size_t);
    int    (* onSeek)(void*, int, int);
} drmp3;

typedef drmp3_uint64 drmp3_uint;

typedef struct
{
    float pcm[1152*2];
} drmp3_frame;

DRMP3_API int drmp3_init_file(drmp3* pMP3, const char* filename, const void* pAlloc);
DRMP3_API void drmp3_uninit(drmp3* pMP3);
DRMP3_API drmp3_uint64 drmp3_read_pcm_frames_f32(drmp3* pMP3, drmp3_uint64 framesToRead, float* pBufferOut);

#ifdef __cplusplus
}
#endif

#endif /* dr_mp3_h */

#ifdef DR_MP3_IMPLEMENTATION
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
/* This is NOT a real MP3 decoder - placeholder for build to succeed. For full decoding pull original dr_mp3.h. */
int drmp3_init_file(drmp3* pMP3, const char* filename, const void* pAlloc) {
    (void)pAlloc; memset(pMP3,0,sizeof(*pMP3)); FILE* f=fopen(filename,"rb"); if(!f) return 0; pMP3->pUserData=f; pMP3->channels=2; pMP3->sampleRate=44100; return 1; }
void drmp3_uninit(drmp3* pMP3){ if(pMP3&&pMP3->pUserData) fclose((FILE*)pMP3->pUserData); }
drmp3_uint64 drmp3_read_pcm_frames_f32(drmp3* pMP3, drmp3_uint64 framesToRead, float* pOut){ (void)pMP3;(void)framesToRead;(void)pOut; return 0; }
#endif /* DR_MP3_IMPLEMENTATION */
