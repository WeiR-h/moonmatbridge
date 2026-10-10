# MoonBit API v0.0.3

The core package is `local/moonmatbridge`. The executable, JSON adapter and JS ABI are separate packages; core parsing performs no host I/O.

| API | Behavior |
| --- | --- |
| `read_mat(Bytes, limits?) -> MatFile raise MatError` | Dense numeric/logical Level 5 input, endian normalization, bounded compressed input |
| `write_mat(Array[NumericArray], compressed?, limits?) -> Bytes raise MatError` | Validate dense arrays, then emit deterministic little-endian MAT |
| `read_document(Bytes, limits?) -> MatDocument raise MatError` | Dense/CSC mixed input; no automatic densification |
| `write_document(Array[MatVariable], compressed?, limits?)` | Validate aggregate dense/CSC metadata and write deterministic MAT |
| `validate_document(variables, limits?)` | Validate public fields, names and aggregate limits without allocating output |
| `raw_sparse_array(name, dtype, shape, row_indices, col_ptrs, real, imag?, nzmax?, is_global?, limits?)` | Validated two-dimensional canonical CSC, including unused stored capacity |
| `SparseArray::to_dense(limits?)` / `NumericArray::to_sparse(limits?)` | Explicit bounded conversion; negative zero and NaN bits are retained |
| `MatDocument::get(name)` / `select(names)` / `convert_storage(name, sparse, limits?)` | Mixed variable lookup/subset or named storage conversion |
| `numeric_array(name, dtype, shape, values, imaginary?, is_global?, limits?)` | Construct from exact `Value` scalars, preserve column-major order |
| `raw_array(name, dtype, shape, real, imag?, is_global?, limits?)` | Construct from canonical little-endian raw bytes; preserve IEEE payload bits |
| `MatFile::select(names, limits?)` | Exact variable subset in requested order; missing/duplicate names fail |
| `NumericArray::permute_axes(axes, limits?)` | Reorder dimensions and both raw payload planes; axes must form a full permutation |
| `NumericArray::reshape(shape, limits?)` | Preserve exact payload and element count while changing column-major dimensions |
| `NumericArray::slice(starts, counts, steps?, limits?)` | Zero-based starts, output counts, positive strides; zero counts are allowed |
| `NumericArray::gather_axis(axis, indices, limits?)` | Ordered/repeated index selection along one zero-based axis |
| `concat_arrays(name, arrays, axis, limits?)` | Compatible rank/type/complex/global flags; equal other dimensions |
| `compare_documents(left, right, max_samples?, limits?)` | Exact contents by variable name; global 0–256 sample budget, default 16 |
| `read_npy(bytes, name, limits?) -> NumericArray raise MatError` | Primitive numerical NPY v1/v2/v3; endian and C/Fortran normalization; no pickle evaluation |
| `write_npy(NumericArray, limits?) -> Bytes raise MatError` | NPY v1.0 export, 64-byte header alignment, Fortran order, interleaved complex data |
| `inflate_zlib(Bytes, max_bytes?) -> Bytes raise MatError` | Bounded RFC 1950 stream decoder with checksum validation |
| `deflate_zlib(Bytes, max_bytes?) -> Bytes raise MatError` | Original deterministic LZ77/fixed-Huffman encoder with stored fallback; input <= 64 MiB |
| `dtype_from_name(String) -> DType raise MatError` | Parse stable dtype names |
| `default_limits() -> Limits` | 64 MiB input/output, 64 MiB cumulative expanded bytes, 4,194,304 elements |

`NumericArray` fields: `name`, `dtype`, `shape`, `real`, `imag`, `is_global`. Payload bytes are immutable; constructors copy the shape. Public fields can be constructed directly, but writers and scalar access revalidate their layout. All arrays must have rank >= 2. Complex data is limited to Float32/Float64. Calling `NumericArray::index` uses default limits while checking public fields.

Array methods: `length()`, `is_complex()`, `index(coordinates)`, `value(linear_index, imaginary?)`. Indexes and coordinates are zero-based. Stride for dimension k is the product of dimensions before k, so `[2,3]` contains `[a00,a10,a01,a11,a02,a12]`.

`MatFile` reports `description`, `little_endian` (original file), and `arrays`. `get(name)` returns `NumericArray?`. Original descriptions are not restored by the deterministic writer; shape, dtype, payload and the supported global flag are restored.

`Value` is one of `Signed(Int64)`, `Unsigned(UInt64)`, `Floating(Double)`, `Boolean(Bool)`. Integer-to-float conversion above 2^53 is rejected; Float32 construction rounds to IEEE binary32 and rejects finite overflow. Integer arrays require integer scalars; narrowing rejects out-of-range values. Real/imaginary payloads always have the same dtype and element count.

`MatError(code, offset, message)` has `code()`, `offset()`, `message()`. Offsets are relative to the current input stream; inside a compressed element, offsets may refer to expanded matrix bytes or the zlib stream. Constructor/writer validation uses offset zero. Do not interpret a compressed error offset as an absolute file position.

The `local/moonmatbridge/interchange` package exports `from_json`, `to_json`, `info`, `document_info`, `error_json`, `sample`, `transform`, `transform_document`, `to_snapshot`, `from_snapshot` and `diff_json`. Wire contracts are documented in [JSON.md](JSON.md). `to_snapshot` returns compact JSON text; `from_snapshot` returns mixed `MatVariable` values.

The JS foreign library exposes:

```javascript
import * as api from './bridge.mjs';
const result = api.json_to_mat(text);
const status = JSON.parse(api.result_status(result));
if (status.status !== 'ok') throw new Error(status.message);
const bytes = api.result_bytes(result); // Uint8Array
console.log(JSON.parse(api.inspect_mat(bytes)));
```

Exports: `npy_to_mat`, `select_mat`, `inspect_mat`, `mat_to_json`, `json_to_mat`, `roundtrip_mat`, `mat_to_npy`, `sample_mat`, `inflate_zlib`, `deflate_zlib`, `compress_mat`, `transform_mat`, `convert_storage`, `mat_to_snapshot`, `snapshot_to_mat`, `compare_mat`, `result_status`, `result_bytes`. Functions returning `BinaryResult` require a status check before consuming bytes. String results contain structured JSON errors on failure. Host-neutral JS exports have no filesystem or Python dependency; Node tests validate them, but a browser UI has not been shipped or tested.

`SparseArray` fields: `name`, `dtype`, two-dimensional `shape`, `row_indices`, `col_ptrs`, `real`, `imag`, `nzmax`, `is_global`. `nnz()` is the final column pointer, including explicit zeros; the slot count can exceed it. Active rows strictly increase within each column. `nzmax` is >= stored slots. Unused row/value slots survive read/write and snapshots. Only float64/logical and complex float64 are supported. `MatDocument` contains `description`, `little_endian`, `variables`. Header text/endian/compression are normalized on write.

`DocumentDifference` reports `content_equal`, `variable_order_changed`, `changed_variables`, `variables`. Metadata differences list dtype, shape, global/complex, storage or CSC pointers/rows/capacity. Comparable value changes are counted separately per real/imaginary plane; samples contain a zero-based linear/CSC-slot index, coordinates and exact before/after bytes. Inactive CSC slots have empty coordinates. Shape/type/storage/index-mapping changes are metadata differences, not fabricated element-by-element matches. File descriptions/endian/compression are excluded, while CSC storage metadata is included. No floating tolerance is applied.

`src/pkg.generated.mbti` and the interfaces under `src/interchange` and `src/bridge` contain the complete compiler-generated signatures. Source consumers can include this local module in a MoonBit workspace; there is no registered Mooncakes package yet.

NPY input supports primitive float32/64, complex64/128, signed/unsigned integers and bool. Header strings must be plain ASCII, the header fits 64 KiB and no duplicate/unknown keys or trailing payload are accepted. Structured, object/pickle, string, datetime, float16 and ambiguous native-endian descriptors are rejected. NPY scalars become `[1,1]` and vectors become `[n,1]`; multidimensional shape is unchanged. Nonzero bool bytes normalize to canonical 1. All numerical bytes, including nonfinite payloads and exact 64-bit integers, are copied without scalar conversion.
