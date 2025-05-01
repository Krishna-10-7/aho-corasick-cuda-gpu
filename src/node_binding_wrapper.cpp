#include <napi.h>
#include <string>
#include <vector>

// Simple wrapper that will be used to communicate with the main executable
Napi::Value Version(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    return Napi::String::New(env, "1.0.0");
}

Napi::Object Init(Napi::Env env, Napi::Object exports) {
    exports.Set("version", Napi::Function::New(env, Version));
    return exports;
}

NODE_API_MODULE(aho_corasick_gpu, Init)
