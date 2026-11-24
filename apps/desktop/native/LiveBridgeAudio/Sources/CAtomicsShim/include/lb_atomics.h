// Minimal lock-free atomics for the real-time audio path (Swift's Synchronization.Atomic needs macOS 15).
#ifndef LB_ATOMICS_H
#define LB_ATOMICS_H
#include <stdatomic.h>
#include <stdint.h>

static inline int64_t lb_atomic_load(const int64_t *p) {
  return atomic_load_explicit((const _Atomic(int64_t) *)p, memory_order_acquire);
}
static inline void lb_atomic_store(int64_t *p, int64_t v) {
  atomic_store_explicit((_Atomic(int64_t) *)p, v, memory_order_release);
}
static inline int64_t lb_atomic_add(int64_t *p, int64_t v) {
  return atomic_fetch_add_explicit((_Atomic(int64_t) *)p, v, memory_order_acq_rel) + v;
}
#endif
