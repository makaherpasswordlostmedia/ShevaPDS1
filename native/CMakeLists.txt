# CMakeLists.txt — desktop build of the SDL2 CRT renderer.
#
# This builds a standalone "pds1_crt_test" executable so the renderer can
# be developed/tested without Android/Gradle in the loop. The same
# crt_renderer.c/.h will later be compiled into the Android native library
# (via ndk-build/CMake + SDL2's Android glue) and driven from a JNI bridge
# instead of native/src/main.c.
#
# Usage (on a machine with SDL2 dev package installed):
#   cd native && mkdir build && cd build
#   cmake .. && cmake --build .
#   ./pds1_crt_test

cmake_minimum_required(VERSION 3.10)
project(pds1_crt LANGUAGES C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

find_package(SDL2 REQUIRED)

add_library(crt_renderer STATIC
    src/crt_renderer.c
)
target_include_directories(crt_renderer PUBLIC include)
target_include_directories(crt_renderer PRIVATE ${SDL2_INCLUDE_DIRS})

add_executable(pds1_crt_test
    src/main.c
)
target_include_directories(pds1_crt_test PRIVATE ${SDL2_INCLUDE_DIRS} include)
target_link_libraries(pds1_crt_test PRIVATE crt_renderer ${SDL2_LIBRARIES})

if (SDL2_LIBRARIES MATCHES "SDL2main" OR TARGET SDL2::SDL2main)
    # Some SDL2 CMake configs expose SDL2::SDL2main; link it if present so
    # SDL_main's WinMain shim works on Windows too.
    if (TARGET SDL2::SDL2main)
        target_link_libraries(pds1_crt_test PRIVATE SDL2::SDL2main)
    endif()
endif()

# On desktop, we need real GLES2 (via ANGLE) or SDL2's bundled
# SDL_opengles2.h shim over desktop GL. SDL2 provides the latter
# automatically when SDL_GL_CONTEXT_PROFILE_ES is requested and
# SDL_opengles2.h is included, so no extra linking is needed beyond SDL2
# itself on most platforms (it dynamically resolves GL entry points).
