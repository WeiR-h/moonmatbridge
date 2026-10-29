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

/* Random-access file transport. Format interpretation remains in MoonBit. */
#ifdef _WIN32
typedef struct _stat64 SourceStat;
#else
typedef struct stat SourceStat;
#endif
typedef struct { int active; int fd; SourceStat status;
#ifdef _WIN32
FILETIME modified;
#endif
} SourceSlot;
static SourceSlot source_slots[16];
int32_t moonmat_source_open(moonbit_bytes_t path, int32_t limit) {
  int slot = 0; while (slot < 16 && source_slots[slot].active) ++slot;
  if (slot == 16) return -1;
#ifdef _WIN32
  wchar_t *wide = wide_path((const char *)path);
  int fd = wide ? _wopen(wide, _O_RDONLY | _O_BINARY) : -1;
  free(wide);
#else
  int fd = open((const char *)path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
#endif
  if (fd < 0) return -1;
  SourceSlot *s = &source_slots[slot];
  if (FSTAT(fd, &s->status) || s->status.st_size < 0 || s->status.st_size > limit) { CLOSE(fd); return -2; }
#ifdef _WIN32
  if ((s->status.st_mode & _S_IFMT) != _S_IFREG || !GetFileTime((HANDLE)_get_osfhandle(fd),NULL,NULL,&s->modified)) { CLOSE(fd); return -1; }
#else
  if (!S_ISREG(s->status.st_mode)) { CLOSE(fd); return -1; }
#endif
  s->active = 1; s->fd = fd; return slot;
}
int32_t moonmat_source_size(int32_t slot) { return slot >= 0 && slot < 16 && source_slots[slot].active ? (int32_t)source_slots[slot].status.st_size : -1; }
int32_t moonmat_source_read(int32_t slot, int32_t offset, moonbit_bytes_t buffer, int32_t start, int32_t length) {
  if (slot < 0 || slot >= 16 || !source_slots[slot].active || offset < 0 || start < 0 || length < 0) return -1;
  int fd = source_slots[slot].fd;
#ifdef _WIN32
  if (_lseeki64(fd, offset, SEEK_SET) < 0) return -1;
  return _read(fd, buffer + start, (unsigned int)length);
#else
  ssize_t count;
  do { count = pread(fd, buffer + start, (size_t)length, offset); } while (count < 0 && errno == EINTR);
  return (int32_t)count;
#endif
}
int32_t moonmat_source_close(int32_t slot) {
  if (slot < 0 || slot >= 16 || !source_slots[slot].active) return 0;
  SourceSlot *s = &source_slots[slot]; SourceStat after;
  int changed = FSTAT(s->fd, &after) != 0;
  if (!changed) changed = after.st_size != s->status.st_size || after.st_mtime != s->status.st_mtime;
#ifdef _WIN32
  FILETIME modified;
  if (!GetFileTime((HANDLE)_get_osfhandle(s->fd),NULL,NULL,&modified) || CompareFileTime(&modified,&s->modified)) changed = 1;
#else
  if (!changed) changed = after.st_mtim.tv_nsec != s->status.st_mtim.tv_nsec || after.st_ctim.tv_nsec != s->status.st_ctim.tv_nsec || after.st_ctime != s->status.st_ctime;
#endif
  if (CLOSE(s->fd)) changed = 1;
  s->active = 0;
  return changed;
}

/* Append to native io.c: bounded positional output transport, no format logic. */
#include <time.h>
typedef struct { int active, fd, created, error; char *target, *temp; } SinkSlot;
static SinkSlot sink_slots[16];
static unsigned int sink_serial;
#ifdef _WIN32
/* Extended absolute paths also keep temporary suffixes within Win32 semantics. */
static wchar_t *sink_wide_path(const char *path) {
  wchar_t *wide = wide_path(path);
  if (!wide) return NULL;
  if (!wcsncmp(wide, L"\\\\?\\", 4)) return wide;
  DWORD size = GetFullPathNameW(wide, 0, NULL, NULL);
  if (!size || size > 32700) { free(wide); return NULL; }
  wchar_t *absolute = malloc(((size_t)size + 1) * sizeof(wchar_t));
  if (!absolute) { free(wide); return NULL; }
  DWORD actual = GetFullPathNameW(wide, size + 1, absolute, NULL);
  free(wide);
  if (!actual || actual > size) { free(absolute); return NULL; }
  for (DWORD i = 0; i < actual; ++i) if (absolute[i] == L'/') absolute[i] = L'\\';
  int unc = !wcsncmp(absolute, L"\\\\", 2);
  size_t prefix = unc ? 8 : 4, skip = unc ? 2 : 0;
  wchar_t *result = malloc((prefix + actual - skip + 1) * sizeof(wchar_t));
  if (result) {
    memcpy(result, unc ? L"\\\\?\\UNC\\" : L"\\\\?\\", prefix * sizeof(wchar_t));
    memcpy(result + prefix, absolute + skip, (actual - skip + 1) * sizeof(wchar_t));
  }
  free(absolute); return result;
}
#endif

int32_t moonmat_sink_begin(moonbit_bytes_t path) {
  int slot = 0; while (slot < 16 && sink_slots[slot].active) ++slot;
  if (slot == 16) return -1;
  size_t length = strlen((const char *)path);
  if (!length || length > SIZE_MAX - 128) return -1;
  SinkSlot *s = &sink_slots[slot];
  memset(s, 0, sizeof(*s)); s->fd = -1;
  s->target = malloc(length + 1); s->temp = malloc(length + 128);
  if (!s->target || !s->temp) { free(s->target); free(s->temp); memset(s,0,sizeof(*s)); return -1; }
  memcpy(s->target, path, length + 1); s->temp[0] = 0; s->active = 1;
  return slot;
}

static int sink_lazy_open(SinkSlot *s) {
#ifdef _WIN32
  wchar_t *target = sink_wide_path(s->target);
  if (!target) { s->error = 1; return -1; }
  DWORD attributes = GetFileAttributesW(target); free(target);
  if (attributes != INVALID_FILE_ATTRIBUTES) { s->error = 3; return -1; }
  unsigned long pid = GetCurrentProcessId();
#else
  struct stat status;
  if (!lstat(s->target, &status)) { s->error = 3; return -1; }
  if (errno != ENOENT) { s->error = 1; return -1; }
  unsigned long pid = (unsigned long)getpid();
#endif
  for (int attempt = 0; attempt < 64; ++attempt) {
    const char *slash = strrchr(s->target, '/');
#ifdef _WIN32
    const char *backslash = strrchr(s->target, '\\');
    if (backslash && (!slash || backslash > slash)) slash = backslash;
    size_t prefix = slash ? (size_t)(slash - s->target + 1) : (strlen(s->target) >= 2 && s->target[1] == ':' ? 2 : 0);
#else
    size_t prefix = slash ? (size_t)(slash - s->target + 1) : 0;
#endif
    snprintf(s->temp, strlen(s->target) + 128, "%.*s.mmb-%lu-%llu-%u.tmp", (int)prefix, s->target, pid, (unsigned long long)time(NULL), ++sink_serial);
#ifdef _WIN32
    wchar_t *temp = sink_wide_path(s->temp);
    int fd = temp ? _wopen(temp, _O_RDWR | _O_CREAT | _O_EXCL | _O_BINARY | _O_NOINHERIT, _S_IREAD | _S_IWRITE) : -1;
    free(temp);
#else
    int fd = open(s->temp, O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC, 0666);
#endif
    if (fd >= 0) { s->fd = fd; s->created = 1; return fd; }
    if (errno != EEXIST) { s->error = 1; return -1; }
  }
  s->error = 1; return -1;
}

int32_t moonmat_sink_write(int32_t slot, int32_t offset, moonbit_bytes_t buffer, int32_t start, int32_t length) {
  if (slot < 0 || slot >= 16 || !sink_slots[slot].active || offset < 0 || start < 0 || length <= 0 || length > 8388608 || offset > 1073741824 - length) return -1;
  SinkSlot *s = &sink_slots[slot];
  if (s->error) return -1;
  if (s->fd < 0 && sink_lazy_open(s) < 0) return -1;
#ifdef _WIN32
  if (_lseeki64(s->fd, offset, SEEK_SET) < 0) { s->error = 1; return -1; }
  int count = _write(s->fd, buffer + start, (unsigned int)length);
#else
  ssize_t count;
  do { count = pwrite(s->fd, buffer + start, (size_t)length, offset); } while (count < 0 && errno == EINTR);
#endif
  if (count <= 0) s->error = 1;
  return (int32_t)count;
}

int32_t moonmat_sink_error(int32_t slot) {
  return slot >= 0 && slot < 16 && sink_slots[slot].active ? sink_slots[slot].error : 1;
}

int32_t moonmat_sink_finish(int32_t slot, int32_t commit, int32_t expected_size) {
  if (slot < 0 || slot >= 16 || !sink_slots[slot].active) return 0;
  SinkSlot *s = &sink_slots[slot];
  if (s->fd >= 0) {
    SourceStat status;
    if (commit && (expected_size < 128 || FSTAT(s->fd, &status) || status.st_size != expected_size)) s->error = 1;
    int fd = s->fd; s->fd = -1;
    if (CLOSE(fd) && !s->error) s->error = 1;
  } else if (commit && !s->error) s->error = 1;
  if (commit && !s->error) {
#ifdef _WIN32
    wchar_t *temp = sink_wide_path(s->temp), *target = sink_wide_path(s->target);
    if (temp && target && MoveFileW(temp, target)) s->created = 0;
    else { DWORD code = temp && target ? GetLastError() : ERROR_INVALID_NAME; s->error = code == ERROR_ALREADY_EXISTS || code == ERROR_FILE_EXISTS ? 3 : 1; }
    free(temp); free(target);
#else
    if (link(s->temp, s->target)) s->error = errno == EEXIST ? 3 : 1;
    /* Final output is committed; cleanup of the extra name is best effort. */
#endif
  }
  if (s->created) {
#ifdef _WIN32
    wchar_t *temp = sink_wide_path(s->temp); if (temp) { DeleteFileW(temp); free(temp); }
#else
    unlink(s->temp);
#endif
  }
  int error = s->error;
  free(s->target); free(s->temp); memset(s, 0, sizeof(*s));
  return error;
}
