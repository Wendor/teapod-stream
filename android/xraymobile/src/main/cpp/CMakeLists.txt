cmake_minimum_required(VERSION 3.22.1)
project(xray_mobile_jni)

add_library(xray_ffi SHARED IMPORTED)
set_target_properties(xray_ffi PROPERTIES
    IMPORTED_LOCATION "${CMAKE_CURRENT_LIST_DIR}/../jniLibs/${ANDROID_ABI}/libxray_ffi.so"
    IMPORTED_NO_SONAME TRUE)

add_library(xray_mobile_jni SHARED xray_mobile_jni.cpp)
set_target_properties(xray_mobile_jni PROPERTIES
    CXX_VISIBILITY_PRESET hidden VISIBILITY_INLINES_HIDDEN YES)
target_include_directories(xray_mobile_jni PRIVATE include)
target_link_libraries(xray_mobile_jni PRIVATE xray_ffi log)
target_link_options(xray_mobile_jni PRIVATE
    "-Wl,-z,max-page-size=16384" "-Wl,-z,common-page-size=16384" "-Wl,--exclude-libs,ALL")
