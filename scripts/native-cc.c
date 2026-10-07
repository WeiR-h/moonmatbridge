// MinGW launcher adapted from the user's Apache-2.0 MoonMMDB development tooling.
// Enable the CRT rand_s declaration and preserve Unicode/spaces in compiler arguments.
#include <wchar.h>
#include <stdlib.h>
#include <process.h>
static wchar_t *quote(const wchar_t *source) {
  wchar_t *result = malloc((wcslen(source) * 2 + 3) * sizeof(wchar_t));
  if (!result) return NULL;
  wchar_t *out = result; *out++ = L'"';
  for (;;) {
    size_t slashes = 0;
    while (*source == L'\\') { slashes++; source++; }
    if (*source == L'"' || *source == 0) slashes *= 2;
    while (slashes--) *out++ = L'\\';
    if (!*source) break;
    if (*source == L'"') *out++ = L'\\';
    *out++ = *source++;
  }
  *out++ = L'"'; *out = 0; return result;
}
int wmain(int argc, wchar_t **argv) {
  const wchar_t *gcc = _wgetenv(L"MOONMAT_GCC");
  if (!gcc) return 2;
  wchar_t **forward = calloc((size_t)argc + 2, sizeof(*forward));
  if (!forward) return 2;
  forward[0] = quote(gcc);
  forward[1] = quote(L"-D_CRT_RAND_S");
  for (int i = 1; i < argc; ++i) forward[i + 1] = quote(argv[i]);
  for (int i = 0; i <= argc; ++i) if (!forward[i]) return 2;
  intptr_t code = _wspawnv(_P_WAIT, gcc, (const wchar_t *const *)forward);
  for (int i = 0; i <= argc; ++i) free(forward[i]);
  free(forward);
  return code < 0 ? 2 : (int)code;
}
