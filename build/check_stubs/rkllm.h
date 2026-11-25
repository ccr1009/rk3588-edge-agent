// ============================================================================
//  rkllm_stub.h —— 仅用于「没有板子、没有真 SDK 时做编译检查」的桩头文件
//
//  这不是真 SDK。它只声明 Agent 实际用到的那部分 API 与结构体字段，
//  用来在 x86/PC 上跑 g++ 语法与类型检查，抓「改了字段名但没改全」这类错。
//
//  ⚠️ 编译出来的二进制**绝对不能上板**，它没有真 NPU 调用。
//  真 SDK 头文件从 Rockchip RKLLM SDK 获取。
// ============================================================================
#ifndef RKLLM_STUB_H
#define RKLLM_STUB_H

#include <cstdint>

// ---- 枚举 ----
typedef enum { RKLLM_RUN_NORMAL = 0,
               RKLLM_RUN_WAITING = 1,
               RKLLM_RUN_FINISH = 2,
               RKLLM_RUN_ERROR  = 3 } LLMCallState;

typedef enum { RKLLM_INPUT_PROMPT = 0,
               RKLLM_INPUT_TOKEN = 1 } RKLLMInputType;

typedef enum { RKLLM_INFER_GENERATE = 0,
               RKLLM_INFER_GET_LAST_HIDDEN_LAYER = 1 } RKLLMInferMode;

typedef enum { RKLLM_QUANT_TYPE_NONE = 0,
               RKLLM_QUANT_TYPE_W8A8 = 1 } RKLLMQuantType;

// ---- 结构体 ----
typedef struct {
    float prefill_time_ms;
    int   prefill_tokens;
    float generate_time_ms;
    int   generate_tokens;
    float memory_usage_mb;
} RKLLMPerfStat;

typedef struct {
    char*         text;          // 本次回调产出的文本片段
    RKLLMPerfStat perf;          // 性能统计（仅 RKLLM_RUN_FINISH 有效）
} RKLLMResult;

typedef int (*LLMResultCallback)(RKLLMResult* result, void* userdata, LLMCallState state);

typedef struct {
    const char* model_path;
    int         max_context_len;
    int         max_new_tokens;
    int         top_k;
    float       top_p;
    float       temperature;
    float       repeat_penalty;
    int         skip_special_token;
    int         ignore_eos_token;
    const char* system_prompt;
    int         base_domain_id;
    LLMResultCallback result_callback;
} RKLLMParam;

typedef struct {
    const char* role;            // "user" / "tool" / "system"
    RKLLMInputType input_type;
    const char* prompt_input;    // 文本输入
} RKLLMInput;

typedef struct {
    RKLLMInferMode mode;
    int  keep_history;           // 多轮会话记忆
    int  keep_system_prompt;     // 清 KV 时是否保留 system prompt
} RKLLMInferParam;

typedef struct {
    LLMResultCallback result_callback;
} RKLLMCallback;

typedef void* LLMHandle;

// ---- API（签名对齐真 SDK 的常用形态，仅占位）----
RKLLMParam rkllm_createDefaultParam(void);

int rkllm_init(LLMHandle* handle, RKLLMParam* param, RKLLMCallback* callback);

int rkllm_run(LLMHandle handle, RKLLMInput* input, RKLLMInferParam* infer,
              void* userdata);

int rkllm_clear_kv_cache(LLMHandle handle, int keep_system_prompt,
                         int* start_pos, int* end_pos);

int rkllm_set_function_tools(LLMHandle handle, const char* system_prompt,
                             const char* tools_json, const char* tool_response_tag);

int rkllm_destroy(LLMHandle handle);

#endif  // RKLLM_STUB_H
