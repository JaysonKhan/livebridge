# Portable C++ core of the LiveBridge audio engine (frame codec, ring buffer, JSON). It has no platform code, so it
# builds and is tested on any host; the Windows runner links it.
cmake_minimum_required(VERSION 3.14)
project(livebridge_core LANGUAGES CXX)

add_library(livebridge_core STATIC
  src/frame_codec.cpp
  src/json.cpp
)
target_include_directories(livebridge_core PUBLIC include)
target_compile_features(livebridge_core PUBLIC cxx_std_17)
if(MSVC)
  target_compile_options(livebridge_core PRIVATE /W4 /utf-8)
else()
  target_compile_options(livebridge_core PRIVATE -Wall -Wextra)
endif()

# Tests are built only when this directory is the top-level project (not when the app's build includes it).
if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
  enable_testing()
  find_package(Threads REQUIRED)
  add_executable(core_tests tests/core_tests.cpp)
  target_link_libraries(core_tests PRIVATE livebridge_core Threads::Threads)
  if(MSVC)
    target_compile_options(core_tests PRIVATE /W4 /utf-8)
  endif()
  add_test(NAME core COMMAND core_tests "${CMAKE_CURRENT_SOURCE_DIR}/../../../../packages/protocol/fixtures/frames.json")
endif()
