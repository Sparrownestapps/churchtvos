// EXPERIMENTAL NDI receiver for the Church TV OS "ndi" build. Written against the NDI SDK v6 C API
// (Processing.NDI.Lib.h). The SDK is not in the repository, so this file has NOT been compiled or run against it yet:
// expect small signature fixes on first build. See NDI-CONTRACT.md.
//
// Design: one receive thread per receiver. Video frames are requested as RGBX and copied straight into the Surface's
// ANativeWindow (CPU copy, simple and works with a rotatable TextureView). Audio is converted to stereo 16-bit and parked
// in a small ring that Kotlin pulls from (no JNI callbacks from native threads).
#include <jni.h>
#include <android/log.h>
#include <android/native_window.h>
#include <android/native_window_jni.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <cstring>
#include <deque>
#include <mutex>
#include <string>
#include <thread>
#include <vector>
#include <strings.h>

#include <Processing.NDI.Lib.h>

#define TAG "ChurchTvNdi"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, TAG, __VA_ARGS__)

namespace {

constexpr int PHASE_SEARCHING = 0, PHASE_CONNECTING = 1, PHASE_STREAMING = 2, PHASE_LOST = 3;
constexpr int64_t STALE_MS = 2000;

int64_t nowMs() {
    using namespace std::chrono;
    return duration_cast<milliseconds>(steady_clock::now().time_since_epoch()).count();
}

std::once_flag g_initOnce;
bool g_initOk = false;
// NDIlib_initialize() once for the life of the process. NDIlib_destroy() is deliberately never called.
bool ensureInit() {
    std::call_once(g_initOnce, [] { g_initOk = NDIlib_initialize(); });
    return g_initOk;
}

struct Receiver {
    std::thread thread;
    std::atomic<bool> running{false};
    std::atomic<int> phase{PHASE_SEARCHING};
    std::atomic<int> width{0}, height{0};
    std::atomic<int64_t> lastFrameAt{-1};  // nowMs() of the newest frame, -1 = none yet
    std::atomic<int> audioRate{0}, audioChannels{2};

    std::string source, address;
    bool wantAudio = false;
    ANativeWindow* window = nullptr;

    std::mutex audioMutex;
    std::condition_variable audioCv;
    std::deque<int16_t> audioRing;  // interleaved stereo, kept short to keep latency low
};

void pushAudio(Receiver* r, const NDIlib_audio_frame_v3_t& a) {
    // SDK v6 delivers planar 32-bit float ("FLTP"); channel_stride_in_bytes is the distance between channels.
    if (a.FourCC != NDIlib_FourCC_audio_type_FLTP || a.no_channels < 1 || a.no_samples < 1 || !a.p_data) return;
    const int ch = a.no_channels;
    const float* left = reinterpret_cast<const float*>(a.p_data);
    const float* right = ch > 1 ? reinterpret_cast<const float*>(a.p_data + a.channel_stride_in_bytes) : left;
    auto toS16 = [](float f) { f = std::max(-1.0f, std::min(1.0f, f)); return static_cast<int16_t>(f * 32767.0f); };
    r->audioRate = a.sample_rate;
    std::lock_guard<std::mutex> lock(r->audioMutex);
    for (int i = 0; i < a.no_samples; i++) {
        r->audioRing.push_back(toS16(left[i]));
        r->audioRing.push_back(toS16(right[i]));
    }
    const size_t cap = static_cast<size_t>(std::max(a.sample_rate, 8000)) * 2 / 2;  // about half a second of stereo
    while (r->audioRing.size() > cap) r->audioRing.pop_front();
    r->audioCv.notify_one();
}

void render(Receiver* r, const NDIlib_video_frame_v2_t& v, int& curW, int& curH) {
    if (!r->window || !v.p_data || v.xres <= 0 || v.yres <= 0) return;
    if (v.FourCC != NDIlib_FourCC_video_type_RGBX && v.FourCC != NDIlib_FourCC_video_type_RGBA) return;
    if (v.xres != curW || v.yres != curH) {
        // The system scales the buffer to the view; Kotlin sizes the view to the picture's shape (fit / fill).
        if (ANativeWindow_setBuffersGeometry(r->window, v.xres, v.yres, WINDOW_FORMAT_RGBX_8888) != 0) return;
        curW = v.xres;
        curH = v.yres;
        r->width = v.xres;
        r->height = v.yres;
    }
    ANativeWindow_Buffer buf;
    if (ANativeWindow_lock(r->window, &buf, nullptr) != 0) return;
    const int rows = std::min<int>(buf.height, v.yres);
    const size_t bytes = static_cast<size_t>(std::min<int>(buf.width, v.xres)) * 4;
    auto* dst = static_cast<uint8_t*>(buf.bits);
    for (int y = 0; y < rows; y++) {
        std::memcpy(dst + static_cast<size_t>(y) * buf.stride * 4, v.p_data + static_cast<size_t>(y) * v.line_stride_in_bytes, bytes);
    }
    ANativeWindow_unlockAndPost(r->window);
}

void receiveLoop(Receiver* r) {
    if (!ensureInit()) {
        LOGW("NDIlib_initialize failed (unsupported CPU or library problem)");
        r->phase = PHASE_LOST;
        return;
    }

    std::string name = r->source;
    std::string url = r->address;
    NDIlib_find_instance_t finder = nullptr;

    if (url.empty()) {
        // Find the source by its exact name (case-insensitive as a second chance).
        NDIlib_find_create_t fc;
        fc.show_local_sources = true;
        fc.p_groups = nullptr;
        fc.p_extra_ips = nullptr;
        finder = NDIlib_find_create_v2(&fc);
        bool found = false;
        while (r->running && !found && finder) {
            NDIlib_find_wait_for_sources(finder, 1000);
            uint32_t n = 0;
            const NDIlib_source_t* list = NDIlib_find_get_current_sources(finder, &n);
            for (int pass = 0; pass < 2 && !found; pass++) {
                for (uint32_t i = 0; i < n && !found; i++) {
                    if (!list[i].p_ndi_name) continue;
                    bool same = pass == 0 ? r->source == list[i].p_ndi_name
                                          : strcasecmp(r->source.c_str(), list[i].p_ndi_name) == 0;
                    if (same) {
                        name = list[i].p_ndi_name;
                        url = list[i].p_url_address ? list[i].p_url_address : "";
                        found = true;
                    }
                }
            }
        }
    }

    NDIlib_recv_instance_t recv = nullptr;
    if (r->running) {
        NDIlib_source_t src;
        src.p_ndi_name = name.c_str();
        src.p_url_address = url.empty() ? nullptr : url.c_str();
        NDIlib_recv_create_v3_t rc;
        rc.source_to_connect_to = src;
        rc.color_format = NDIlib_recv_color_format_RGBX_RGBA;
        rc.bandwidth = NDIlib_recv_bandwidth_highest;
        rc.allow_video_fields = false;
        rc.p_ndi_recv_name = "Church TV OS";
        recv = NDIlib_recv_create_v3(&rc);
        if (!recv) LOGW("NDIlib_recv_create_v3 failed");
        else { r->phase = PHASE_CONNECTING; LOGI("connecting to %s", name.c_str()); }
    }
    // A finder that has done its job is released; the receiver reconnects on its own if the source drops and comes back.
    if (finder) { NDIlib_find_destroy(finder); finder = nullptr; }

    int curW = 0, curH = 0;
    while (r->running && recv) {
        NDIlib_video_frame_v2_t video;
        NDIlib_audio_frame_v3_t audio;
        switch (NDIlib_recv_capture_v3(recv, &video, r->wantAudio ? &audio : nullptr, nullptr, 100)) {
            case NDIlib_frame_type_video:
                render(r, video, curW, curH);
                NDIlib_recv_free_video_v2(recv, &video);
                r->lastFrameAt = nowMs();
                r->phase = PHASE_STREAMING;
                break;
            case NDIlib_frame_type_audio:
                pushAudio(r, audio);
                NDIlib_recv_free_audio_v3(recv, &audio);
                break;
            default:
                break;
        }
        int64_t last = r->lastFrameAt.load();
        if (last >= 0 && nowMs() - last > STALE_MS) r->phase = PHASE_LOST;
    }

    if (recv) NDIlib_recv_destroy(recv);
}

Receiver* from(jlong h) { return reinterpret_cast<Receiver*>(h); }

}  // namespace

extern "C" {

JNIEXPORT jlong JNICALL Java_com_churchtvos_ndi_NdiNative_create(JNIEnv*, jobject) { return reinterpret_cast<jlong>(new Receiver()); }

JNIEXPORT void JNICALL Java_com_churchtvos_ndi_NdiNative_start(JNIEnv* env, jobject, jlong handle, jstring source, jstring address, jobject surface, jboolean audio) {
    Receiver* r = from(handle);
    if (!r || r->running) return;
    const char* s = env->GetStringUTFChars(source, nullptr);
    r->source = s ? s : "";
    if (s) env->ReleaseStringUTFChars(source, s);
    r->address.clear();
    if (address) {
        const char* a = env->GetStringUTFChars(address, nullptr);
        if (a) { r->address = a; env->ReleaseStringUTFChars(address, a); }
    }
    r->wantAudio = audio == JNI_TRUE;
    r->window = ANativeWindow_fromSurface(env, surface);  // holds its own reference
    r->phase = PHASE_SEARCHING;
    r->width = r->height = 0;
    r->lastFrameAt = -1;
    r->running = true;
    r->thread = std::thread(receiveLoop, r);
}

JNIEXPORT void JNICALL Java_com_churchtvos_ndi_NdiNative_stop(JNIEnv*, jobject, jlong handle) {
    Receiver* r = from(handle);
    if (!r) return;
    r->running = false;
    r->audioCv.notify_all();
    if (r->thread.joinable()) r->thread.join();
    if (r->window) { ANativeWindow_release(r->window); r->window = nullptr; }
}

JNIEXPORT void JNICALL Java_com_churchtvos_ndi_NdiNative_destroy(JNIEnv* env, jobject self, jlong handle) {
    Java_com_churchtvos_ndi_NdiNative_stop(env, self, handle);
    delete from(handle);
}

JNIEXPORT void JNICALL Java_com_churchtvos_ndi_NdiNative_snapshot(JNIEnv* env, jobject, jlong handle, jlongArray out) {
    Receiver* r = from(handle);
    if (!r || env->GetArrayLength(out) < 6) return;
    int64_t last = r->lastFrameAt.load();
    jlong v[6] = {r->phase.load(), r->width.load(), r->height.load(), last < 0 ? -1 : nowMs() - last, r->audioRate.load(), 2};
    env->SetLongArrayRegion(out, 0, 6, v);
}

JNIEXPORT jint JNICALL Java_com_churchtvos_ndi_NdiNative_readAudio(JNIEnv* env, jobject, jlong handle, jshortArray out) {
    Receiver* r = from(handle);
    if (!r) return 0;
    const jsize cap = env->GetArrayLength(out);
    std::unique_lock<std::mutex> lock(r->audioMutex);
    r->audioCv.wait_for(lock, std::chrono::milliseconds(50), [&] { return !r->audioRing.empty() || !r->running; });
    jsize n = static_cast<jsize>(std::min<size_t>(r->audioRing.size(), static_cast<size_t>(cap)));
    n -= n % 2;  // whole stereo frames
    if (n <= 0) return 0;
    std::vector<int16_t> tmp(r->audioRing.begin(), r->audioRing.begin() + n);
    r->audioRing.erase(r->audioRing.begin(), r->audioRing.begin() + n);
    lock.unlock();
    env->SetShortArrayRegion(out, 0, n, tmp.data());
    return n;
}

}  // extern "C"
