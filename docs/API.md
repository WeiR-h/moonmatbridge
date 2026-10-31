# MoonBit API v0.1.10

The core package is `WeiR-h/moonmatbridge`. The executable, JSON adapter and JS ABI are separate packages; core parsing performs no host I/O.

| API | Behavior |
| --- | --- |
| `read_tree(Bytes, limits?, tree_limits?) -> MatTree raise MatError` | All documented base classes including recursive cell/struct/char/legacy object |
| `read_selected(Bytes, names, limits?, tree_limits?) -> MatTree raise MatError` | Validate the whole file but construct only requested roots, in requested order; an empty selection still validates everything |
| `inspect_roots(Bytes, limits?, tree_limits?) -> Array[MatRootInfo] raise MatError` | Fully validated root names, raw class IDs, shapes, global/complex/logical flags and compression; no cached offsets |
| `write_tree(Array[MatNode], compressed?, limits?, tree_limits?) -> Bytes raise MatError` | Preflight the entire tree, then write deterministic little-endian Level 5 |
| `utf8_char_array(name, shape, text, is_global?, limits?) -> CharArray` | Validated UTF8 scalar-count dimensions; anonymous names allowed for container children |
| `default_tree_limits() -> TreeLimits` | Depth 64, nodes 65,536, fields per struct 4,096 |
| `read_mat(Bytes, limits?) -> MatFile raise MatError` | Dense numeric/logical Level 5 input, endian normalization, bounded compressed input |
| `write_mat(Array[NumericArray], compressed?, limits?) -> Bytes raise MatError` | Validate dense arrays, then emit deterministic little-endian MAT |
| `read_document(Bytes, limits?) -> MatDocument raise MatError` | Dense/CSC mixed input; no automatic densification |
| `write_document(Array[MatVariable], compressed?, limits?)` | Validate aggregate dense/CSC metadata and write deterministic MAT |
| `validate_document(variables, limits?)` | Validate public fields, names and aggregate limits without allocating output |
| `raw_sparse_array(name, dtype, shape, row_indices, col_ptrs, real, imag?, nzmax?, is_global?, limits?)` | Validated two-dimensional CSC storage, including unused stored capacity |
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

The `WeiR-h/moonmatbridge/interchange` package exports `from_json`, `to_json`, `info`, `document_info`, `tree_info`, `error_json`, `sample`, `transform`, `transform_document`, `to_snapshot`, `from_snapshot` and `diff_json`. Wire contracts are documented in [JSON.md](JSON.md). `to_snapshot` returns compact JSON text; `from_snapshot` returns mixed `MatVariable` values.

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

`SparseArray` fields: `name`, `dtype`, two-dimensional `shape`, `row_indices`, `col_ptrs`, `real`, `imag`, `nzmax`, `is_global`. `nnz()` is the final column pointer, including explicit zeros; the slot count can exceed it. Active row order and duplicate slots are preserved within each column. `nzmax` is >= stored slots. Unused row/value slots survive read/write and snapshots. Only float64/logical and complex float64 are supported. `MatDocument` contains `description`, `little_endian`, `variables`. Header text/endian/compression are normalized on write.

`DocumentDifference` reports `content_equal`, `variable_order_changed`, `changed_variables`, `variables`. Metadata differences list dtype, shape, global/complex, storage or CSC pointers/rows/capacity. Comparable value changes are counted separately per real/imaginary plane; samples contain a zero-based linear/CSC-slot index, coordinates and exact before/after bytes. Inactive CSC slots have empty coordinates. Shape/type/storage/index-mapping changes are metadata differences, not fabricated element-by-element matches. File descriptions/endian/compression are excluded, while CSC storage metadata is included. No floating tolerance is applied.

`src/pkg.generated.mbti` and the interfaces under `src/interchange` and `src/bridge` contain the complete compiler-generated signatures. Install the exact registry version with `moon add WeiR-h/moonmatbridge@0.1.10`, then import the core and/or interchange package. `examples/registry_consumer` contains a consumer that uses only these public interfaces; the registry verification script resolves a fresh copy and checks its source bytes before running all three targets.

NPY input supports primitive float32/64, complex64/128, signed/unsigned integers and bool. Header strings must be plain ASCII, the header fits 64 KiB and no duplicate/unknown keys or trailing payload are accepted. Structured, object/pickle, string, datetime, float16 and ambiguous native-endian descriptors are rejected. NPY scalars become `[1,1]` and vectors become `[n,1]`; multidimensional shape is unchanged. Nonzero bool bytes normalize to canonical 1. All numerical bytes, including nonfinite payloads and exact 64-bit integers, are copied without scalar conversion.

## Recursive mixed values

`MatNode` is `Numeric(NumericArray)`, `Csc(SparseArray)`, `Character(CharArray)`, `Cell(CellArray)` or `Structure(StructArray)`. `MatTree` reports description, original little_endian and variables; `get(name)` and `select(names)` support all nodes.

`CharArray` has name, shape, encoding, data, is_global. `CharEncoding` includes Int8Text, UInt8Text, UInt16Text, Utf8, Utf16, Utf32. Multi-byte data units are canonical little-endian. UTF8 dimensions count Unicode scalars; UTF16/UINT16 dimensions count 16-bit units, preserving surrogate units without lossy decoding. UTF32 requires valid Unicode scalars. See [compatibility plan](COMPATIBILITY.md) for cross-tool Unicode verification limits.

`CellArray` has name, shape, values, is_global; values are column-major. `StructArray` adds fields and class_name; values are element-major then field order (`element * fields.length() + field`). None class_name means struct; Some(name) means the documented legacy mxOBJECT data class. No constructors or MATLAB code execute. Empty fields and empty shapes are supported.

Public structures may be constructed directly. Nested node names may be empty; root names must be nonempty. Writers revalidate public fields and enforce recursive limits before encoding. Defaults add max_depth=64, max_nodes=65536, max_fields=4096; custom hard bounds are depth<=128, nodes<=1048576, fields<=65536. max_elements charges container positions plus leaf elements/stored CSC slots across the whole tree. The same budget applies to compressed roots.

CLI info/roundtrip/compress/select and corresponding JS exports use this API. Older read_mat/read_document and numeric JSON/NPY/transforms/snapshot/diff retain their documented domains and reject containers explicitly; they never silently skip mixed values. `tree_info` returns recursive metadata with children in the same order as values, fields and class_name for structs/objects, encoding/byte count for characters. It does not serialize character payload as JSON text.

## 递归精确比较

`compare_trees(left : MatTree, right : MatTree, max_samples?, limits?, tree_limits?) -> TreeDifference`。结构化路径与报告定义见 [TREE_DIFF.md](TREE_DIFF.md)。`validate_tree(variables, limits?, tree_limits?)` 可单独执行无 MAT 输出分配的完整预检。

## 完整混合树快照

`@interchange.to_tree_snapshot(variables, limits?, tree_limits?) -> String` 与 `from_tree_snapshot(text, limits?, tree_limits?) -> Array[MatNode]` 保留递归结构和原始存储，见 [TREE_SNAPSHOT.md](TREE_SNAPSHOT.md)。

## 文件数据源

`MatSource`、`SourceLimits`、`default_source_limits()` 及 `read_tree_from` / `read_selected_from` / `inspect_roots_from` 见 [文件数据源](SOURCES.md)。

## 对称浮点容差比较

`compare_trees_close(left, right, atol?, rtol?, equal_nan?, max_samples?, limits?, tree_limits?) -> TreeCloseDifference`。独立报告、CLI 参数文件和 JS 导出见 [TREE_CLOSE.md](TREE_CLOSE.md)。精确比较接口和格式保持兼容。

## Explicit MAT name codecs

MAT read/write families accept optional `name_encoding`, default `NameEncoding::Utf8`; use `NameEncoding::Latin1` explicitly for legacy 8-bit names. It applies to variable, field and legacy class names, separately from character payload encoding. See [NAME_ENCODING.md](NAME_ENCODING.md).

## 稳定接口约定

1.x 保持已有调用、公共字段及既有 JSON 格式的含义。类型或参数的不兼容变更、公开枚举分支造成的穷举变化采用大版本；兼容功能采用次版本，修复采用补丁版本。错误码含义稳定，诊断文字与具体偏移不作为可缓存文件定位接口。精确树比较单独报告根顺序；容差比较将根顺序计为元数据差异，两者保持各自既有语义。

内存、文件、比较和快照接口分别执行 Limits/SourceLimits/TreeLimits。名称转为 Unicode 文本后，UTF-8 体积可能大于旧编码；组合接口时可显式设置适合结果的资源额度。资源额度与峰值内存分别衡量。

## Bounded output

`MatSink`、`WriteLimits`、`default_write_limits()` 和 `write_tree_to` 见 [文件写出](SINKS.md)。已有内存接口与 JS BinaryResult 导出保持兼容；新增 JS `make_sink`、`roundtrip_mat_to`、`select_source_mat_to`、`tree_snapshot_to_sink` 及对应 `*_with_options`，返回含最终字节数的状态 JSON。
