// File and command-line transport only. No MAT, JSON, NPY or compression logic.
#include <moonbit.h>
#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <sys/stat.h>
#include <fcntl.h>
#ifdef _WIN32
#include <windows.h>
#include <io.h>
#define CLOSE _close
#define FDOPEN _fdopen
#define FILENO _fileno
#define FSTAT _fstat64
static LPWSTR *wide_args;
static int wide_count;
#else
#include <unistd.h>
#include <signal.h>
#define CLOSE close
#define FDOPEN fdopen
#define FILENO fileno
#define FSTAT fstat
#endif
static int io_error;
int32_t moonmat_error(void) { return io_error; }
int32_t moonmat_emit_error(moonbit_bytes_t bytes, int32_t size) {
  return fwrite(bytes, 1, (size_t)size, stderr) == (size_t)size && !fflush(stderr) ? 0 : 1;
}
void moonmat_init(void) {
#ifdef _WIN32
  _setmode(_fileno(stdout), _O_BINARY);
  _setmode(_fileno(stderr), _O_BINARY);
  typedef LPWSTR *(WINAPI *ArgvFn)(LPCWSTR, int *);
  HMODULE library = LoadLibraryW(L"shell32.dll");
  ArgvFn parse = library ? (ArgvFn)GetProcAddress(library, "CommandLineToArgvW") : NULL;
  if (parse) wide_args = parse(GetCommandLineW(), &wide_count);
  if (library) FreeLibrary(library);
#else
  signal(SIGPIPE, SIG_IGN);
#endif
}
int32_t moonmat_arg_count(int32_t fallback) {
#ifdef _WIN32
  if (wide_args) return wide_count;
#endif
  return fallback;
}
moonbit_string_t moonmat_arg(int32_t index, moonbit_string_t fallback) {
#ifdef _WIN32
  if (wide_args && index >= 0 && index < wide_count) {
    int length = (int)wcslen(wide_args[index]);
    moonbit_string_t result = moonbit_make_string_raw(length);
    memcpy(result, wide_args[index], (size_t)length * sizeof(wchar_t));
    return result;
  }
#endif
  moonbit_incref(fallback);
  return fallback;
}
#ifdef _WIN32
static wchar_t *wide_path(const char *path) {
  int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, NULL, 0);
  wchar_t *result = count ? malloc((size_t)count * sizeof(wchar_t)) : NULL;
  if (result && !MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, result, count)) {
    free(result); result = NULL;
  }
  return result;
}
#endif
moonbit_bytes_t moonmat_read(moonbit_bytes_t path, int32_t limit) {
  io_error = 0;
  FILE *file = NULL;
#ifdef _WIN32
  wchar_t *wide = wide_path((const char *)path);
  if (wide) file = _wfopen(wide, L"rb");
  free(wide);
#else
  int fd = open((const char *)path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
  if (fd >= 0) { file = FDOPEN(fd, "rb"); if (!file) CLOSE(fd); }
#endif
  if (!file) { io_error = 1; return moonbit_make_bytes(0, 0); }
#ifdef _WIN32
  struct _stat64 status;
  int regular = !FSTAT(FILENO(file), &status) && (status.st_mode & _S_IFMT) == _S_IFREG;
#else
  struct stat status;
  int regular = !FSTAT(FILENO(file), &status) && S_ISREG(status.st_mode);
#endif
  if (!regular || status.st_size < 0 || status.st_size > limit) {
    io_error = regular ? 2 : 1; fclose(file); return moonbit_make_bytes(0, 0);
  }
  int32_t size = (int32_t)status.st_size;
  moonbit_bytes_t result = moonbit_make_bytes(size, 0);
  if (fread(result, 1, (size_t)size, file) != (size_t)size || fgetc(file) != EOF || ferror(file)) {
    io_error = 1; moonbit_decref(result); result = moonbit_make_bytes(0, 0);
  }
  if (fclose(file)) io_error = 1;
  return result;
}
int32_t moonmat_save(moonbit_bytes_t path, moonbit_bytes_t bytes, int32_t size) {
  int fd;
#ifdef _WIN32
  wchar_t *wide = wide_path((const char *)path);
  if (!wide) return 1;
  fd = _wopen(wide, _O_WRONLY | _O_CREAT | _O_EXCL | _O_BINARY, _S_IREAD | _S_IWRITE);
#else
  fd = open((const char *)path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0666);
#endif
  int saved_errno = errno;
  if (fd < 0) {
#ifdef _WIN32
    free(wide);
#endif
    return saved_errno == EEXIST ? 3 : 1;
  }
  FILE *file = FDOPEN(fd, "wb");
  int failed = !file;
  if (file) { failed = fwrite(bytes, 1, (size_t)size, file) != (size_t)size; if (fclose(file)) failed = 1; }
  else CLOSE(fd);
  if (failed) {
#ifdef _WIN32
    _wremove(wide);
#else
    unlink((const char *)path);
#endif
  }
#ifdef _WIN32
  free(wide);
#endif
  return failed ? 1 : 0;
}
