# Third-party components and format references

Product code is original, AI-assisted MoonBit implementation under Apache-2.0, except the small compiler launcher adaptation noted below. Python, SciPy, NumPy and Node zlib are verification tools, not MAT runtime implementations used by the product.

| Component/reference | Role | License/credit |
| --- | --- | --- |
| [MoonBit core](https://github.com/moonbitlang/core) and compiler runtime | Standard library, generated JS/native/Wasm runtime | Apache-2.0; MoonBit contributors. The native executable embeds runtime code. |
| Local MoonMMDB `scripts/native-cc.c` | Adapted MinGW compiler argument quoting / `_CRT_RAND_S` build launcher | Apache-2.0; user's MoonMMDB tooling. Development only, no file-format logic. |
| [MathWorks MAT-file format](https://www.mathworks.com/help/pdf_doc/matlab/matfile_format.pdf) | MAT Level 5 specification reference | MathWorks documentation. No documentation text or proprietary code bundled. |
| [SciPy MATLAB I/O](https://github.com/scipy/scipy/tree/v1.15.3/scipy/io/matlab) | Independent fixture producer and consumer; format behavior reference | BSD-3-Clause; SciPy developers. Installed only in optional verification environment; no source copied. |
| [NumPy NPY format](https://numpy.org/doc/stable/reference/generated/numpy.lib.format.html) | NPY descriptor/order/header contract; independent consumer | NumPy documentation; verification library BSD-3-Clause. No source copied. |
| [RFC 1950](https://www.rfc-editor.org/rfc/rfc1950), [RFC 1951](https://www.rfc-editor.org/rfc/rfc1951) | zlib/DEFLATE format and canonical Huffman coding | IETF/RFC authors. Original bounded decoder, no external decompressor dependency. |
| Node.js built-in zlib | Differential oracle for 704 streams | Node.js / zlib notices; development only, not bundled into native executable. |

`matio`, `mat4js` and `moon-npy` were considered during topic/ecosystem research. They are not dependencies, and their implementation code is not incorporated into this project. In particular, no GPL `mat4js` code is used.

AI assistance covers implementation and documentation. Executable claims are tied to `verification/reports`, with source SHA-256 fingerprints; public publishing, MATLAB execution and award outcomes are separate, unverified steps.
