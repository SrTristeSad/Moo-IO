#include <jni.h>
#include <node.h>
#include <android/log.h>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <unistd.h>
extern "C" JNIEXPORT jint JNICALL
Java_org_love2d_android_MooIONodeBridge_start(
    JNIEnv *env,jclass,jobjectArray arguments,jobjectArray variables,jstring directory) {
    const char *dir=env->GetStringUTFChars(directory,nullptr);
    if(chdir(dir)!=0) {
        __android_log_print(ANDROID_LOG_ERROR,"MooIO-Host","chdir failed: %s",dir);
        env->ReleaseStringUTFChars(directory,dir);
        return -2;
    }
    env->ReleaseStringUTFChars(directory,dir);
    for(jsize i=0;i<env->GetArrayLength(variables);i++) {
        auto item=(jstring)env->GetObjectArrayElement(variables,i);
        const char *raw=env->GetStringUTFChars(item,nullptr);
        std::string entry(raw);
        auto idx=entry.find('=');
        if(idx!=std::string::npos)
            setenv(entry.substr(0,idx).c_str(),entry.substr(idx+1).c_str(),1);
        env->ReleaseStringUTFChars(item,raw);
        env->DeleteLocalRef(item);
    }
    const jsize count=env->GetArrayLength(arguments);
    if(count<2 || count>8)return -3;
    std::vector<std::string> strargs;
    size_t total=0;
    for(jsize i=0;i<count;i++) {
        auto item=(jstring)env->GetObjectArrayElement(arguments,i);
        const char *s=env->GetStringUTFChars(item,nullptr);
        strargs.emplace_back(s);
        total+=strargs.back().size()+1;
        env->ReleaseStringUTFChars(item,s);
        env->DeleteLocalRef(item);
    }
    // libuv may rewrite argument contents, which must be contiguous.
    std::vector<char> arena(total);
    std::vector<char*> argv;
    size_t offset=0;
    for(const auto &a:strargs) {
        argv.push_back(arena.data()+offset);
        memcpy(arena.data()+offset,a.c_str(),a.size()+1);
        offset+=a.size()+1;
    }
    __android_log_print(ANDROID_LOG_INFO,"MooIO-Host","node::Start invoked");
    return (jint)node::Start((int)count,argv.data());
}
