#ifndef CONECTA_VOICE_H
#define CONECTA_VOICE_H
#include <stdint.h>
#if defined(__GNUC__)
#define CV_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#else
#define CV_EXPORT
#endif
#ifdef __cplusplus
extern "C" {
#endif
CV_EXPORT const char *conecta_voice_version(void);
CV_EXPORT int32_t conecta_voice_begin(void);
CV_EXPORT void conecta_voice_cancel(int32_t token);
CV_EXPORT void conecta_voice_release(int32_t token);
CV_EXPORT int32_t conecta_voice_transcribe(int32_t token,const char *model,const char *audio,char **text);
CV_EXPORT void conecta_voice_free(char *text);
#ifdef __cplusplus
}
#endif
#endif
