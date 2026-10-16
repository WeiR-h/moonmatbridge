///|
fn sparse_matrix(
  bytes : Bytes,
  outer : Element,
  little : Bool,
  limits : Limits,
  nested? : Bool = false,
) -> SparseArray raise MatError {
  let end = outer.start + outer.size
  let flags = tag(bytes, outer.start, end, little)
  if flags.kind != 6 || flags.size != 8 {
    fail("invalid-flags", outer.start, "Expected sparse miUINT32 flags")
  }
  let bits = bits_at(bytes, flags.start, 4, little).to_uint()
  if (bits & 255U) != 5U || (bits & 0xfffff100U) != 0U {
    fail("unsupported-flags", flags.start, "Unknown sparse flags")
  }
  let capacity = bits_at(bytes, flags.start + 4, 4, little)
  if capacity > limits.max_elements.to_uint64() {
    fail("element-limit", flags.start, "Sparse nzmax exceeds limit")
  }
  let dtype = if (bits & 512U) != 0U { Logical } else { Float64 }
  let complex = (bits & 2048U) != 0U
  if complex && dtype == Logical {
    fail("unsupported-complex", flags.start, "Logical sparse cannot be complex")
  }
  let dims = tag(bytes, flags.next, end, little)
  if dims.kind != 5 || dims.size != 8 {
    fail("invalid-shape", dims.start, "Sparse matrices need two dimensions")
  }
  let shape = Array::makei(2, i => {
    bits_at(bytes, dims.start + i * 4, 4, little).to_uint().reinterpret_as_int()
  })
  if shape[0] < 0 || shape[1] < 0 || shape[1] >= limits.max_elements {
    fail(
      "invalid-shape",
      dims.start,
      "Sparse dimensions or column pointers exceed bounds",
    )
  }
  let name = tag(bytes, dims.next, end, little)
  if name.kind != 1 ||
    (!nested && name.size == 0) ||
    name.size > limits.max_name_bytes {
    fail("invalid-name", name.start, "Expected bounded sparse variable name")
  }
  let text = @utf8.decode(bytes[name.start:name.start + name.size]) catch {
    _ => {
      fail("invalid-name", name.start, "Sparse name must be UTF-8")
      ""
    }
  }
  let ir = tag(bytes, name.next, end, little)
  let jc = tag(bytes, ir.next, end, little)
  if ir.kind != 5 ||
    ir.size % 4 != 0 ||
    ir.size / 4 > limits.max_elements ||
    jc.kind != 5 ||
    jc.size != (shape[1] + 1) * 4 {
    fail(
      "invalid-sparse",
      ir.start,
      "Expected bounded miINT32 CSC row indices and column pointers",
    )
  }
  let rows = Array::makei(ir.size / 4, i => {
    bits_at(bytes, ir.start + i * 4, 4, little).to_uint().reinterpret_as_int()
  })
  let cols = Array::makei(jc.size / 4, i => {
    bits_at(bytes, jc.start + i * 4, 4, little).to_uint().reinterpret_as_int()
  })
  let values = tag(bytes, jc.next, end, little)
  if dtype == Float64 && values.kind != 9 {
    fail(
      "unsupported-sparse-dtype",
      values.start,
      "Sparse numerical storage must be float64",
    )
  }
  let real = numeric_payload(bytes, values, dtype, rows.length(), little)
  let (imag, next) = if complex {
    let values = tag(bytes, values.next, end, little)
    if values.kind != 9 {
      fail(
        "unsupported-sparse-dtype",
        values.start,
        "Sparse imaginary storage must be float64",
      )
    }
    (
      Some(numeric_payload(bytes, values, dtype, rows.length(), little)),
      values.next,
    )
  } else {
    (None, values.next)
  }
  if next != end {
    fail("trailing-matrix-data", next, "Unexpected sparse matrix data")
  }
  let result : SparseArray = {
    name: text,
    dtype,
    shape,
    row_indices: rows,
    col_ptrs: cols,
    real,
    imag,
    nzmax: capacity.to_int(),
    is_global: (bits & 1024U) != 0U,
  }
  ignore(validate_sparse(result, limits, allow_empty=nested))
  result
}
