#include <jni.h>
#include <node.h>
#include <android/log.h>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <unistd.h>
#include <pthread.h>
#include <errno.h>
#include <cstdio>

static int stdoutPipe[2],stderrPipe[2];
static void *capturePipe(void *arg) {
    int fd = *static_cast<int*>(arg);
    char buf[2048];
    ssize_t count;
    while ((count=read(fd,buf,sizeof(buf)-1))>0) {
        buf[count]='\0';
        __android_log_write(fd==stdoutPipe[0]?ANDROID_LOG_INFO:ANDROID_LOG_ERROR,
                            "MooIO-Node",buf);
    }
    return nullptr;
}
static void setupCapture() {
    if(pipe(stdoutPipe)==0 && pipe(stderrPipe)==0) {
        dup2(stdoutPipe[1],STDOUT_FILENO);
        dup2(stderrPipe[1],STDERR_FILENO);
        close(stdoutPipe[1]);
        close(stderrPipe[1]);
        pthread_t o,e;
        pthread_create(&o,nullptr,capturePipe,&stdoutPipe[0]);
        pthread_create(&e,nullptr,capturePipe,&stderrPipe[0]);
        pthread_detach(o);pthread_detach(e);
    }
}
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
    setupCapture();
    int exit=(int)node::Start((int)count,argv.data());
    __android_log_print(ANDROID_LOG_ERROR,"MooIO-Host","node::Start exited with %d",exit);
    return (jint)exit;
}
