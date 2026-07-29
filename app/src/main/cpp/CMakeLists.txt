# app/src/main/cpp/CMakeLists.txt
#
# NDK build for the Android target. Produces a single shared library,
# libpds1native.so, that:
#   - links SDL2 (built as its own shared lib, see SDL2_DIR below)
#   - contains crt_renderer.c (the vector CRT renderer, shared with the
#     desktop build in native/CMakeLists.txt)
#   - contains jni_bridge.c (Machine <-> renderer JNI glue)
#   - contains android_main.c (SDL2 android_main() entry point + the
#     SDL event loop that drives input/UI, see step 2/3)
#
# SDL2 itself is NOT vendored in this repo (no network access when this
# was generated). To build:
#   1. Download SDL2 source (release-2.30.x) from https://github.com/libsdl-org/SDL
#   2. Extract it to app/src/main/cpp/SDL2  (so this dir contains SDL2's
#      own CMakeLists.txt, include/, src/, android-project/, etc.)
#   3. Sync Gradle — externalNativeBuild will pick this file up
#      automatically (see app/build.gradle's externalNativeBuild block).
#
# Directory layout expected:
#   app/src/main/cpp/
#     CMakeLists.txt        <- this file
#     SDL2/                 <- vendored SDL2 source tree (step 2 above)
#     jni_bridge.c           -> ../../../../native/src/jni_bridge.c (symlink/copy)
#     crt_renderer.c/.h      -> ../../../../native/src/crt_renderer.c etc.
#     android_main.c         <- SDL2 android_main + event loop (added in step 2/3)
#
# For simplicity this CMakeLists reaches up into ../../../../native so the
# same crt_renderer.c/.h used by the desktop build is compiled here too —
# no file duplication.

cmake_minimum_required(VERSION 3.10)
project(pds1native LANGUAGES C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# ---------------------------------------------------------------------
# SDL2 (vendored source tree — see instructions above)
# ---------------------------------------------------------------------
set(SDL2_SRC_DIR ${CMAKE_CURRENT_SOURCE_DIR}/SDL2)

if(NOT EXISTS ${SDL2_SRC_DIR}/CMakeLists.txt)
    message(FATAL_ERROR
        "SDL2 source not found at ${SDL2_SRC_DIR}. "
        "Download SDL2 (release-2.30.x) from https://github.com/libsdl-org/SDL "
        "and extract it into app/src/main/cpp/SDL2 before building. "
        "See the comment at the top of this CMakeLists.txt.")
endif()

# SDL2's own CMake build produces the SDL2 shared lib + sets up Android glue
# (SDL_android_main.c, JNI entry points for SDLActivity, etc.)
set(SDL_SHARED ON CACHE BOOL "" FORCE)
set(SDL_STATIC OFF CACHE BOOL "" FORCE)
add_subdirectory(${SDL2_SRC_DIR} SDL2-build)

# ---------------------------------------------------------------------
# Shared renderer core (same source as the desktop build)
# ---------------------------------------------------------------------
set(NATIVE_CORE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../../../../native)

add_library(pds1native SHARED
    ${NATIVE_CORE_DIR}/src/crt_renderer.c
    ${NATIVE_CORE_DIR}/src/jni_bridge.c
    android_main.c
    ui_widgets.c
    input_bridge.c
)

target_include_directories(pds1native PRIVATE
    ${NATIVE_CORE_DIR}/include
    ${SDL2_SRC_DIR}/include
)

target_link_libraries(pds1native PRIVATE
    SDL2
    GLESv2
    log
    android
)

# Android NDK's GLES2 headers are used automatically via the standard NDK
# sysroot; no extra include path needed beyond the toolchain defaults.
