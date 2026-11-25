# Portable C++ core of the LiveBridge audio engine (frame codec, ring buffer, JSON). It has no platform code, so it
# builds and is tested on any host; the Windows runner links it.
cmake_minimum_required(VERSION 3.14)
project(livebridge_core LANGUAGES CXX)

file(GLOB LIVEBRIDGE_CORE_SOURCES CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/src/*.cpp")
add_library(livebridge_core STATIC ${LIVEBRIDGE_CORE_SOURCES})
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
  # Every tests/<name>_tests.cpp is one test program; each gets the shared frame fixtures as its argument.
  file(GLOB LIVEBRIDGE_TEST_SOURCES CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/tests/*_tests.cpp")
  foreach(test_source ${LIVEBRIDGE_TEST_SOURCES})
    get_filename_component(test_name ${test_source} NAME_WE)
    add_executable(${test_name} ${test_source})
    target_include_directories(${test_name} PRIVATE tests)
    target_link_libraries(${test_name} PRIVATE livebridge_core Threads::Threads)
    if(MSVC)
      target_compile_options(${test_name} PRIVATE /W4 /utf-8)
    endif()
    add_test(NAME ${test_name} COMMAND ${test_name} "${CMAKE_CURRENT_SOURCE_DIR}/../../../../packages/protocol/fixtures/frames.json")
  endforeach()
endif()
