#include <napi.h>
#include <vector>
#include <string>
#include "aho_corasick.h"
#include "aho_corasick_gpu.cuh"

class MatchWorker : public Napi::AsyncWorker {
public:
    MatchWorker(Napi::Function& callback, std::string text, std::vector<std::string> patterns)
        : Napi::AsyncWorker(callback), text(text), patterns(patterns) {}

    ~MatchWorker() {}

    void Execute() override {
        try {
            // Build CPU automaton
            auto cpu_automaton = buildAutomatonCPU(patterns);
            
            // Transfer to GPU
            auto gpu_automaton = transferAutomatonToGPU(cpu_automaton);
            
            // Search for patterns
            auto matches = searchGPU(text, gpu_automaton);
            
            // Count matches per pattern
            std::vector<int> pattern_counts(patterns.size(), 0);
            for (const auto& match : matches) {
                if (match.pattern_index >= 0 && match.pattern_index < patterns.size()) {
                    pattern_counts[match.pattern_index]++;
                }
            }
            
            // Store results
            for (size_t i = 0; i < patterns.size(); i++) {
                results.push_back({patterns[i], pattern_counts[i]});
            }
        } catch (const std::exception& e) {
            SetError(e.what());
        }
    }

    void OnOK() override {
        Napi::HandleScope scope(Env());
        Napi::Array result_array = Napi::Array::New(Env(), results.size());
        
        for (size_t i = 0; i < results.size(); i++) {
            Napi::Object match = Napi::Object::New(Env());
            match.Set("pattern", results[i].pattern);
            match.Set("count", results[i].count);
            result_array[i] = match;
        }
        
        Callback().Call({Env().Null(), result_array});
    }

private:
    std::string text;
    std::vector<std::string> patterns;
    
    struct Result {
        std::string pattern;
        int count;
    };
    std::vector<Result> results;
};

Napi::Value FindMatches(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    
    // Check arguments
    if (info.Length() < 2) {
        Napi::TypeError::New(env, "Wrong number of arguments").ThrowAsJavaScriptException();
        return env.Null();
    }
    
    if (!info[0].IsString() || !info[1].IsArray()) {
        Napi::TypeError::New(env, "Wrong arguments").ThrowAsJavaScriptException();
        return env.Null();
    }
    
    // Extract text and patterns
    std::string text = info[0].As<Napi::String>().Utf8Value();
    Napi::Array patterns_array = info[1].As<Napi::Array>();
    std::vector<std::string> patterns;
    
    for (uint32_t i = 0; i < patterns_array.Length(); i++) {
        Napi::Value val = patterns_array[i];
        if (val.IsString()) {
            patterns.push_back(val.As<Napi::String>().Utf8Value());
        } else {
            Napi::TypeError::New(env, "Pattern must be a string").ThrowAsJavaScriptException();
            return env.Null();
        }
    }
    
    // Create promise
    Napi::Promise::Deferred deferred = Napi::Promise::Deferred::New(env);
    
    // Create and queue the async worker
    MatchWorker* worker = new MatchWorker(
        Napi::Function::New(env, [deferred](const Napi::CallbackInfo& info) {
            Napi::Env env = info.Env();
            
            if (info[0].IsNull()) {
                deferred.Resolve(info[1]);
            } else {
                deferred.Reject(info[0].As<Napi::Error>().Value());
            }
            
            return env.Undefined();
        }),
        text,
        patterns
    );
    
    worker->Queue();
    
    return deferred.Promise();
}

Napi::Object Init(Napi::Env env, Napi::Object exports) {
    exports.Set("findMatches", Napi::Function::New(env, FindMatches));
    return exports;
}

NODE_API_MODULE(aho_corasick_gpu, Init)
