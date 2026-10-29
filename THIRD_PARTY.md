# Third-party components and format references

Product code is original MoonBit implementation under Apache-2.0, except the small compiler launcher adaptation noted below. Python, SciPy, NumPy and Node zlib are verification tools, not MAT runtime implementations used by the product.

| Component/reference | Role | License/credit |
| --- | --- | --- |
| [MoonBit core](https://github.com/moonbitlang/core) and compiler runtime | Standard library, generated JS/native/Wasm runtime | Apache-2.0; MoonBit contributors. The native executable embeds runtime code. |
| [Microsoft C/C++ Build Tools](https://visualstudio.microsoft.com/license-terms/) | Windows C compiler and static C runtime; existing Windows SDK supplies platform interfaces | Microsoft license terms; compiler/SDK packages are development tools and are excluded from source and Mooncakes archives. Native distribution uses the supported static CRT configuration. |
| Local MoonMMDB `scripts/native-cc.c` | Adapted MinGW compiler argument quoting / `_CRT_RAND_S` build launcher | Apache-2.0; user's MoonMMDB tooling. Development only, no file-format logic. |
| [MathWorks MAT-file format](https://www.mathworks.com/help/pdf_doc/matlab/matfile_format.pdf) | MAT Level 5 specification reference | MathWorks documentation. No documentation text or proprietary code bundled. |
| [SciPy MATLAB I/O](https://github.com/scipy/scipy/tree/v1.15.3/scipy/io/matlab) | Independent fixture producer and consumer; format behavior reference | BSD-3-Clause; SciPy developers. Installed only in optional verification environment; no source copied. |
| [NumPy NPY format](https://numpy.org/doc/stable/reference/generated/numpy.lib.format.html) | NPY descriptor/order/header contract; independent producer and consumer | NumPy documentation; verification library BSD-3-Clause. No source copied. |
| [RFC 1950](https://www.rfc-editor.org/rfc/rfc1950), [RFC 1951](https://www.rfc-editor.org/rfc/rfc1951) | zlib/DEFLATE format and canonical Huffman coding | IETF/RFC authors. Original bounded decoder, no external decompressor dependency. |
| [RFC 3629](https://www.rfc-editor.org/rfc/rfc3629) | UTF-8 scalar validity and overlong/surrogate bounds | Format reference for original allocation-free scanner; standard decoder used as independent test oracle. |
| Node.js built-in zlib | Differential oracle for 704 streams | Node.js / zlib notices; development only, not bundled into native executable. |

`matio`, `mat4js` and `moon-npy` were considered during topic/ecosystem research. They are not dependencies, and their implementation code is not incorporated into this project. In particular, no GPL `mat4js` code is used.

Executable behavior is recorded in `verification/reports` with source SHA-256 fingerprints, tool versions and independent public download checks.
