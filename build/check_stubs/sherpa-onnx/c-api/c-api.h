// ============================================================================
//  sherpa-onnx/c-api/c-api.h —— 仅用于「没有板子、没有 sherpa 静态包时」的
//  编译检查桩头文件。不是真 SDK。
//
//  只声明 tts_daemon.cpp 实际用到的类型与字段，用来在 PC 上跑 g++ 类型检查。
//  ⚠️ 编出来的二进制不能当 TTS 用。真头文件随 sherpa-onnx 静态包发布。
// ============================================================================
#ifndef SHERPA_ONNX_C_API_STUB_H
#define SHERPA_ONNX_C_API_STUB_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct SherpaOnnxOfflineTts SherpaOnnxOfflineTts;

typedef struct {
    const char* model;
    const char* tokens;
    const char* lexicon;
    const char* dict_dir;
    const char* data_dir;
    float noise_scale;
    float noise_scale_w;
    float length_scale;
} SherpaOnnxOfflineTtsVitsModelConfig;

typedef struct {
    const char* model;
    const char* tokens;
    const char* lexicon;
    const char* dict_dir;
    const char* data_dir;
} SherpaOnnxOfflineTtsMatchaModelConfig;

typedef struct {
    SherpaOnnxOfflineTtsVitsModelConfig   vits;
    SherpaOnnxOfflineTtsMatchaModelConfig matcha;
    int         num_threads;
    const char* provider;
    int         debug;
} SherpaOnnxOfflineTtsModelConfig;

typedef struct {
    SherpaOnnxOfflineTtsModelConfig model;
    int  max_num_sentences;
    const char* rule_fsts;
    const char* rule_fars;
    float silence_scale;
} SherpaOnnxOfflineTtsConfig;

typedef struct {
    const float* samples;
    int32_t      n;
    int32_t      sample_rate;
} SherpaOnnxGeneratedAudio;

const SherpaOnnxOfflineTts* SherpaOnnxCreateOfflineTts(const SherpaOnnxOfflineTtsConfig* config);
void SherpaOnnxDestroyOfflineTts(const SherpaOnnxOfflineTts* tts);
int32_t SherpaOnnxOfflineTtsSampleRate(const SherpaOnnxOfflineTts* tts);
int32_t SherpaOnnxOfflineTtsNumSpeakers(const SherpaOnnxOfflineTts* tts);
const SherpaOnnxGeneratedAudio* SherpaOnnxOfflineTtsGenerate(
    const SherpaOnnxOfflineTts* tts, const char* text, int32_t sid, float speed);
void SherpaOnnxDestroyOfflineTtsGeneratedAudio(const SherpaOnnxGeneratedAudio* p);

#ifdef __cplusplus
}
#endif

#endif  // SHERPA_ONNX_C_API_STUB_H
