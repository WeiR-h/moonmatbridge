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
