/* Development-only transport/clock/RSS adapter; all codec work is MoonBit. */
#include "../moonmat/io.c"
#ifdef _WIN32
#include <psapi.h>
double moonmat_now(void) {
  LARGE_INTEGER counter, frequency;
  QueryPerformanceCounter(&counter); QueryPerformanceFrequency(&frequency);
  return 1000.0 * (double)counter.QuadPart / (double)frequency.QuadPart;
}
double moonmat_peak(void) {
  PROCESS_MEMORY_COUNTERS counters;
  if (!K32GetProcessMemoryInfo(GetCurrentProcess(), &counters, sizeof(counters))) return -1;
  return (double)counters.PeakWorkingSetSize;
}
#else
#include <time.h>
#include <sys/resource.h>
double moonmat_now(void) {
  struct timespec value;
  clock_gettime(CLOCK_MONOTONIC, &value);
  return value.tv_sec * 1000.0 + value.tv_nsec / 1000000.0;
}
double moonmat_peak(void) {
  struct rusage value;
  if (getrusage(RUSAGE_SELF, &value)) return -1;
  return (double)value.ru_maxrss * 1024.0;
}
#endif

int32_t moonmat_bench_remove(moonbit_bytes_t path) {
#ifdef _WIN32
  wchar_t *wide = sink_wide_path((const char *)path);
  if (!wide) return -1;
  int result = DeleteFileW(wide) ? 0 : -1;
  free(wide); return result;
#else
  return remove((const char *)path);
#endif
}
