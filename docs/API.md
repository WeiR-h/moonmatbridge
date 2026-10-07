# MoonBit API v0.0.1

The core package is `local/moonmatbridge`. The executable, JSON adapter and JS ABI are separate packages; core parsing performs no host I/O.

| API | Behavior |
| --- | --- |
| `read_mat(Bytes, limits?) -> MatFile raise MatError` | Dense numeric/logical Level 5 input, endian normalization, bounded compressed input |
| `write_mat(Array[NumericArray], limits?) -> Bytes raise MatError` | Validate all arrays, then emit deterministic uncompressed little-endian MAT |
| `numeric_array(name, dtype, shape, values, imaginary?, is_global?, limits?)` | Construct from exact `Value` scalars, preserve column-major order |
| `raw_array(name, dtype, shape, real, imag?, is_global?, limits?)` | Construct from canonical little-endian raw bytes; preserve IEEE payload bits |
| `write_npy(NumericArray, limits?) -> Bytes raise MatError` | NPY v1.0 export, 64-byte header alignment, Fortran order, interleaved complex data |
| `inflate_zlib(Bytes, max_bytes?) -> Bytes raise MatError` | Bounded RFC 1950 stream decoder with checksum validation |
| `dtype_from_name(String) -> DType raise MatError` | Parse stable dtype names |
| `default_limits() -> Limits` | 64 MiB input/output, 64 MiB cumulative expanded bytes, 4,194,304 elements |

`NumericArray` fields: `name`, `dtype`, `shape`, `real`, `imag`, `is_global`. Payload bytes are immutable; constructors copy the shape. Public fields can be constructed directly, but writers always revalidate them. All arrays must have rank >= 2. Complex data is limited to Float32/Float64. Calling `NumericArray::index` uses default limits while checking public fields.

Array methods: `length()`, `is_complex()`, `index(coordinates)`, `value(linear_index, imaginary?)`. Indexes and coordinates are zero-based. Stride for dimension k is the product of dimensions before k, so `[2,3]` contains `[a00,a10,a01,a11,a02,a12]`.

`MatFile` reports `description`, `little_endian` (original file), and `arrays`. `get(name)` returns `NumericArray?`. Original descriptions are not restored by the deterministic writer; shape, dtype, payload and the supported global flag are restored.

`Value` is one of `Signed(Int64)`, `Unsigned(UInt64)`, `Floating(Double)`, `Boolean(Bool)`. Integer-to-float conversion above 2^53 is rejected; Float32 construction rounds to IEEE binary32 and rejects finite overflow. Integer arrays require integer scalars; narrowing rejects out-of-range values. Real/imaginary payloads always have the same dtype and element count.

`MatError(code, offset, message)` has `code()`, `offset()`, `message()`. Offsets are relative to the current input stream; inside a compressed element, offsets may refer to expanded matrix bytes or the zlib stream. Constructor/writer validation uses offset zero. Do not interpret a compressed error offset as an absolute file position.

The `local/moonmatbridge/interchange` package exports `from_json`, `to_json`, `info`, `error_json`, and `sample`. JSON wire behavior is documented in [JSON.md](JSON.md).

The JS foreign library exposes:

```javascript
import * as api from './bridge.mjs';
const result = api.json_to_mat(text);
const status = JSON.parse(api.result_status(result));
if (status.status !== 'ok') throw new Error(status.message);
const bytes = api.result_bytes(result); // Uint8Array
console.log(JSON.parse(api.inspect_mat(bytes)));
```

Exports: `inspect_mat`, `mat_to_json`, `json_to_mat`, `roundtrip_mat`, `mat_to_npy`, `sample_mat`, `inflate_zlib`, `result_status`, `result_bytes`. Functions returning `BinaryResult` require a status check before consuming bytes. Errors never return partial converted data. Host-neutral JS exports use Bytes/strings and have no filesystem or Python dependency; Node tests validate them, but a browser UI has not been shipped or tested in v0.0.1.

`src/pkg.generated.mbti` and the interfaces under `src/interchange` and `src/bridge` contain the complete compiler-generated signatures. Source consumers can include this local module in a MoonBit workspace; there is no registered Mooncakes package yet.
