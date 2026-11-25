#ifndef RUNNER_SCOPED_HANDLE_H_
#define RUNNER_SCOPED_HANDLE_H_

#include <windows.h>

// Owns one kernel handle (an event, a process) and closes it when it goes out of scope. Null means none.
class ScopedHandle {
 public:
  explicit ScopedHandle(HANDLE handle = nullptr) : handle_(handle) {}
  ~ScopedHandle() { reset(); }
  ScopedHandle(const ScopedHandle&) = delete;
  ScopedHandle& operator=(const ScopedHandle&) = delete;

  HANDLE get() const { return handle_; }
  // Closes the handle held so far, if any, and takes `handle` instead.
  void reset(HANDLE handle = nullptr) {
    if (handle_ != nullptr) ::CloseHandle(handle_);
    handle_ = handle;
  }

 private:
  HANDLE handle_;
};

#endif  // RUNNER_SCOPED_HANDLE_H_
