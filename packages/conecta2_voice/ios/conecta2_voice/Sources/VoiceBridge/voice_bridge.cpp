#include "include/voice_bridge.h"
#include <whisper.h>
#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <memory>
#include <string>
#include <thread>
#include <vector>
namespace {
std::atomic<bool> busy{false}, cancelled{false};
std::atomic<int32_t> generation{0};
bool abort_inference(void *) { return cancelled.load(); }
void silent_log(ggml_log_level, const char *, void *) {}
uint32_t le32(const unsigned char *b) { return uint32_t(b[0])|(uint32_t(b[1])<<8)|(uint32_t(b[2])<<16)|(uint32_t(b[3])<<24); }
uint16_t le16(const unsigned char *b) { return uint16_t(b[0])|(uint16_t(b[1])<<8); }
bool read_wav(const char *path, std::vector<float> &samples) {
    std::ifstream file(path,std::ios::binary|std::ios::ate);
    if(!file || file.tellg()>1100000 || file.tellg()<44) return false;
    const auto length=static_cast<size_t>(file.tellg());file.seekg(0);
    std::vector<unsigned char> bytes(length);file.read(reinterpret_cast<char*>(bytes.data()),length);
    if(!file || std::memcmp(bytes.data(),"RIFF",4) || std::memcmp(bytes.data()+8,"WAVE",4)) return false;
    bool valid=false;
    for(size_t pos=12;pos+8<=length;) {
        const auto size=le32(bytes.data()+pos+4);const auto data=pos+8;
        if(size>length-data) return false;
        if(!std::memcmp(bytes.data()+pos,"fmt ",4)) {
            if(size<16) return false;
            valid=le16(bytes.data()+data)==1 && le16(bytes.data()+data+2)==1 &&
                  le32(bytes.data()+data+4)==16000 && le16(bytes.data()+data+14)==16;
        }
        if(!std::memcmp(bytes.data()+pos,"data",4)) {
            if(!valid || size%2 || size/2>480000 || size/2<8000) return false;
            samples.reserve(size/2);
            for(size_t i=0;i<size;i+=2) samples.push_back(static_cast<int16_t>(le16(bytes.data()+data+i))/32768.0f);
            return true;
        }
        pos=data+size+(size%2);
    }
    return false;
}
}
extern "C" {
const char *conecta_voice_version() { return whisper_version(); }
int32_t conecta_voice_begin() {
    bool expected=false;if(!busy.compare_exchange_strong(expected,true)) return -1;
    cancelled=false;return ++generation;
}
void conecta_voice_cancel(int32_t token) { if(generation==token) cancelled=true; }
void conecta_voice_release(int32_t token) { if(generation==token) busy=false; }
void conecta_voice_free(char *text) { std::free(text); }
int32_t conecta_voice_transcribe(int32_t token,const char *model,const char *audio,char **text) {
    if(!text || !model || !audio || generation!=token || !busy) return -1;
    *text=nullptr;
    struct Release { int32_t token; ~Release(){conecta_voice_release(token);} } release{token};
    try {
        if(cancelled) return -2;
        std::vector<float> samples;if(!read_wav(audio,samples)) return -3;
        double energy=0;for(auto s:samples) energy+=s*s;
        if(std::sqrt(energy/samples.size())<.003) return 0;
        whisper_log_set(silent_log,nullptr);
        auto options=whisper_context_default_params();options.use_gpu=false;
        std::unique_ptr<whisper_context,decltype(&whisper_free)> context(whisper_init_from_file_with_params(model,options),whisper_free);
        if(!context) return -4;
        if(cancelled) return -2;
        auto params=whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
        params.n_threads=std::max(1u,std::min(4u,std::thread::hardware_concurrency()));
        params.language="es";params.translate=false;params.no_context=true;params.no_timestamps=true;
        params.print_progress=false;params.print_realtime=false;params.print_timestamps=false;params.print_special=false;
        params.suppress_blank=true;params.suppress_nst=true;params.temperature=0;params.temperature_inc=0;
        params.abort_callback=abort_inference;params.abort_callback_user_data=nullptr;
        if(whisper_full(context.get(),params,samples.data(),static_cast<int>(samples.size()))!=0) return cancelled?-2:-5;
        if(cancelled) return -2;
        std::string result;
        for(int i=0;i<whisper_full_n_segments(context.get());++i) {
            const char *segment=whisper_full_get_segment_text(context.get(),i);
            if(segment) result+=segment;
        }
        *text=static_cast<char*>(std::malloc(result.size()+1));if(!*text) return -6;
        std::memcpy(*text,result.c_str(),result.size()+1);return 0;
    } catch(...) { return -7; }
}
}
