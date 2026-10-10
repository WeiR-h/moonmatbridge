# Format and resource contract

MAT Level 5 uses a 128-byte header, a 0x0100 version and an `IM` or `MI` endian marker. Variables are `miMATRIX` elements or a single zlib-compressed `miMATRIX` inside `miCOMPRESSED`. Standard elements use 8-byte tag/alignment; small elements inline up to four payload bytes. Compressed elements use their exact byte count without extra 8-byte padding, matching MATLAB/SciPy behavior.

The reader validates every enclosed length before consuming it: flags, dimension vector, name, real data and optional imaginary data. Dense numeric arrays require exactly those fields and no trailing matrix content. It recovers the declared MAT class when the storage tag differs, with checked conversion. All canonical payloads are little-endian and column-major. Same-class storage is normalized by byte swaps rather than floating-point conversion, preserving NaN payload bits. Logical values normalize to 0/1; snapshots preserve this canonical payload, rather than an arbitrary nonzero byte from the original file.

The writer emits standard elements, a fixed description and zero subsystem offset, with exact type-specific payloads. It validates arrays and the conservative uncompressed size before assembling the file. Output can be uncompressed or deterministic compressed. Original file description, byte order and compression layout are not preserved.

The zlib implementation is MoonBit code, independent of Node/Python/C zlib. It handles stored, fixed and dynamic Huffman blocks, bounded overlapping backreferences, header/window constraints, reserved symbols, complete stream end and Adler-32. Preset dictionaries are rejected. The decoder originated in v0.0.1 backed by differential tests, not a claim of a formal proof or a comprehensive fuzzing campaign.

The v0.0.3 encoder uses a 32 KiB LZ77 window, at most 32 hash-chain probes per position, matches up to 258 bytes and fixed Huffman coding. If fixed output exceeds the stored-block size, it falls back to stored blocks. Input is capped at 64 MiB even with larger custom Limits. Compression is deterministic and useful for repetitive data; no optimal ratio or throughput claim is made. Compressed writes also enforce cumulative expanded size, and may reject an output whose compressed bytes would fit when the conservative uncompressed budget would not.

CSC sparse Level 5 uses class 5, two dimensions, miINT32 row indices/column pointers, numerical or logical real data and optional double imaginary data. Column pointers start at zero, are monotone, and end at used entries <= stored slots <= nzmax. Active row indices must be strictly increasing per column; noncanonical order/duplicates fail explicitly. Float64, logical and complex float64 are supported. Inactive capacity slots and nzmax are preserved. Shape product is not charged as dense elements during sparse read/write: column pointers, indices, stored values and bytes are bounded. Only explicit densification validates the full shape product and allocates dense storage. NPY export of a sparse variable returns `explicit-densification-required`.

| Default limit | Value |
| --- | --- |
| MAT input / binary output | 64 MiB |
| Cumulative expanded compressed streams | 64 MiB per file |
| Total dense elements + stored CSC slots | 4,194,304 per MAT file |
| Variables | 4,096 |
| Dimensions | 32 |
| UTF-8 variable-name bytes | 1,024 |

These are bounds, not measured peak memory guarantees. Decoded arrays and expanded streams coexist, and JSON representations can be substantially larger than binary data. CLI loads whole files; very large datasets and streaming are deferred. User-supplied Limits are also bounded (file/expanded bytes <= 1 GiB, elements <= 134,217,728, variables <= 65,536, rank <= 128, name bytes <= 65,536), so signed size arithmetic remains controlled.

Representative error codes: `invalid-header`, `unsupported-version`, `unsupported-v7.3`, `unsupported-subsystem`, `unsupported-class`, `unsupported-flags`, `unsupported-complex`, `truncated-tag`, `truncated-data`, `truncated-padding`, `invalid-small-tag`, `invalid-shape`, `payload-size`, `invalid-name`, `duplicate-name`, `value-type`, `value-range`, `precision-loss`, `file-limit`, `element-limit`, `expanded-limit`, `variable-limit`, `invalid-limits`, `invalid-zlib`, `invalid-json`, `output-exists`.

Duplicate MAT variable names fail rather than replacing data. Unsupported classes fail the entire read; the library does not offer a partial metadata scan. UTF-8 names and files with no subsystem metadata are the supported name/metadata profile.

Transform plans allow at most 256 operations. Steps must be positive; output counts may be zero. Every step validates aggregate output limits. Snapshot JSON uses raw hex and conservative compact-JSON size bounds, so it can be refused even when the binary MAT fits. Snapshot text is capped at max_file_bytes and nesting depth 64. Exact diff samples are globally capped at 256, but all comparable values are counted. These limits constrain work/storage rather than proving a peak memory or latency ceiling.

NPY export contains one array, rank/dtype and `fortran_order=True`; complex data is interleaved. It uses NPY v1.0 with a little-endian 16-bit header length and 64-byte header alignment. Only plain numeric/logical arrays are exported; there is no object pickle or NPZ output.

References: [MathWorks MAT file documentation](https://www.mathworks.com/help/pdf_doc/matlab/matfile_format.pdf), [SciPy's Level 5 I/O implementation](https://github.com/scipy/scipy/tree/v1.15.3/scipy/io/matlab), [NumPy NPY specification](https://numpy.org/doc/stable/reference/generated/numpy.lib.format.html), [RFC 1950](https://www.rfc-editor.org/rfc/rfc1950), [RFC 1951](https://www.rfc-editor.org/rfc/rfc1951).

NPY input accepts primitive numerical/logical versions 1.0, 2.0 and 3.0, with a bounded 64 KiB plain ASCII header. Dictionary order is arbitrary, but its three keys must occur once. C-order and big-endian payloads normalize by exact byte copies; complex components split into two planes. Scalar/vector rank is explicitly promoted to MAT rank two. Input must have the exact payload size; Python expressions, unknown keys, structured/object/pickle descriptors and trailing data fail. Bool bytes normalize to 0/1.
