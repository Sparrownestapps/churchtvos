cmake_minimum_required(VERSION 3.22.1)
project(ndi_jni LANGUAGES CXX)

# EXPERIMENTAL. The NDI SDK is not in the repository. Unpack it so that this exists:
#   tv-app/app/ndi-sdk/include/Processing.NDI.Lib.h
#   tv-app/app/ndi-sdk/lib/<abi>/libndi.so        (abi = arm64-v8a, armeabi-v7a)
if(NOT DEFINED NDI_SDK_DIR OR NOT EXISTS "${NDI_SDK_DIR}/include/Processing.NDI.Lib.h")
  message(FATAL_ERROR "NDI SDK not found. Put the NDI SDK for Android (include/ and lib/) in tv-app/app/ndi-sdk/. See NDI-CONTRACT.md.")
endif()
if(NOT EXISTS "${NDI_SDK_DIR}/lib/${ANDROID_ABI}/libndi.so")
  message(FATAL_ERROR "NDI SDK has no lib/${ANDROID_ABI}/libndi.so")
endif()

add_library(ndi SHARED IMPORTED)
set_target_properties(ndi PROPERTIES IMPORTED_LOCATION "${NDI_SDK_DIR}/lib/${ANDROID_ABI}/libndi.so")

add_library(ndi_jni SHARED ndi_jni.cpp)
target_include_directories(ndi_jni PRIVATE "${NDI_SDK_DIR}/include")
target_compile_features(ndi_jni PRIVATE cxx_std_17)
target_link_libraries(ndi_jni ndi android log)
# Android 15+ devices with 16 KB pages.
target_link_options(ndi_jni PRIVATE "-Wl,-z,max-page-size=16384")
