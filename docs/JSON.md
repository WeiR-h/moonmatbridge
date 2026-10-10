# JSON interchange: moonmatbridge/1

```json
{
  "schema": "moonmatbridge/1",
  "order": "column-major",
  "arrays": [
    {
      "name": "signal",
      "dtype": "float64",
      "shape": [2, 2],
      "real": [1, 2, 3, 4],
      "imag": null,
      "global": false
    },
    {
      "name": "sample_id",
      "dtype": "uint64",
      "shape": [1, 2],
      "real": ["9007199254740993", "18446744073709551615"]
    }
  ]
}
```

Root fields are exactly `schema`, `order`, `arrays`. Each array allows `name`, `dtype`, `shape`, `real`, optional `imag`, optional `global`. Unknown fields are rejected, so a misspelled `shape` or an accidental order conversion does not silently change the data.

Dtypes are `float32`, `float64`, `int8`, `uint8`, `int16`, `uint16`, `int32`, `uint32`, `int64`, `uint64`, `logical`.

- All values are flat and column-major. `[2,2]` with `[1,2,3,4]` is the matrix `[[1,3],[2,4]]`.
- Shapes require at least two nonnegative integer dimensions. Zero-length arrays use an empty value list.
- `int64` and `uint64` **always** use base-10 strings, including small values. JSON numbers are rejected for these types, preventing JavaScript's 2^53 rounding from entering the data path.
- Smaller integers use JSON numbers; fractions, wrong signedness and overflow fail.
- Float arrays use finite JSON numbers or the strings `"NaN"`, `"Infinity"`, `"-Infinity"`, `"-0"`. JSON numeric overflow is rejected; use explicit markers for nonfinite values.
- Logical values are JSON booleans.
- `imag` is null/absent for real data; otherwise it has the same count/type as `real`, and the dtype must be floating.
- `global` defaults to false. It maps to the supported MAT global flag.

MAT->MAT and MAT->NPY preserve IEEE payload bytes. JSON preserves numeric meaning, dtype, dimensions, complex components and negative zero. **JSON normalizes NaN payload/sign encoding** and Float32 text is rounded back to binary32 on import; use binary output for bit-level scientific archives.

The parser uses a 64-level JSON depth limit and bounded file size. It does not parse arbitrary NumPy pickles or execute Python expressions.

## Lossless archive: moonmatbridge/snapshot/1

`snapshot` / `restore` use a separate strict schema. Existing `dump` / `pack` keep the readable dense-only `moonmatbridge/1` contract.

```json
{
  "schema": "moonmatbridge/snapshot/1",
  "order": "column-major",
  "byte_order": "little",
  "variables": [
    {"storage": "dense", "name": "bits", "dtype": "float64", "shape": [1, 1], "global": false, "real_hex": "420000000000f87f", "imag_hex": null},
    {"storage": "csc", "name": "s", "dtype": "float64", "shape": [1000000, 2], "global": false, "real_hex": "000000000000f03f", "imag_hex": null, "row_indices": [999999], "col_ptrs": [0, 0, 1], "nzmax": 1}
  ]
}
```

All fields shown are required; CSC additionally requires row indices, column pointers and nzmax. Unknown fields/order/storage, malformed hex, duplicate variable names and invalid layouts fail. Hex pairs represent canonical little-endian planes in column-major order and preserve all bits. Snapshot text uses compact JSON, a conservative preallocation bound and the configured file-byte limit; hex may use more than twice the binary payload. Input depth is bounded at 64. Array contents/global flags/CSC capacity survive; source header description, endian marker and original compression bytes do not.

## Transform plan: moonmatbridge/transform/1

See [the executable example](../examples/transform-plan.json). Root fields are exactly `schema`, `operations`, at most 256 operations. Every operation requires `op`, `name` and its matching parameters:

| op | Additional fields |
| --- | --- |
| slice | starts, counts, optional steps |
| gather | axis, indices |
| reshape | shape |
| permute | axes |
| concat | inputs, axis; name is a new output variable |

Indices/axes/starts are zero-based; counts are output dimensions, steps are positive. Gather permits repetition. Operations run in sequence on dense variables, preserving exact payloads and unprocessed CSC variables. Unknown fields, missing names, incompatible arrays and aggregate limits fail before any CLI output file is created.

## Difference report: moonmatbridge/diff/1

`comparison=by-name-bit-exact`, `content_equal`, `variable_order_changed` and `changed_variables` summarize the result. Each variable has `equal/changed/added/removed` status, metadata reasons, real/imaginary differing-slot counts, `truncated` and samples. Samples contain plane, zero-based index, coordinates and before/after hex bytes. The default global sample limit is 16 (core API permits 0–256); counts cover all comparable values. Metadata changes that prevent positional correspondence are reported without misleading scalar counts. See [RECIPES.md](RECIPES.md) for the CLI 0/2/1 exit codes.
