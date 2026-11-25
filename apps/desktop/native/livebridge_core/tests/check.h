// The whole test harness: CHECK prints its location on failure; finish() reports and gives the exit code.
#pragma once

#include <cstdio>

namespace livebridge_test {
inline int failures = 0;
inline int checks = 0;

inline int finish() {
  std::printf("%d checks, %d failed\n", checks, failures);
  return failures == 0 ? 0 : 1;
}
}  // namespace livebridge_test

#define CHECK(condition)                                                              \
  do {                                                                                \
    livebridge_test::checks++;                                                        \
    if (!(condition)) {                                                               \
      livebridge_test::failures++;                                                    \
      std::printf("FAILED %s:%d: %s\n", __FILE__, __LINE__, #condition);              \
    }                                                                                 \
  } while (0)
