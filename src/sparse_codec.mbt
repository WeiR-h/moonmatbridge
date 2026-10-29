///|
/// CSC has fixed-width int32 units. Decode a word directly rather than running
/// the generic variable-width scalar loop for every stored row and pointer.
#inline
fn csc_index_at(bytes : Bytes, offset : Int, little : Bool) -> Int {
  let word = bytes[offset].to_uint() |
    (bytes[offset + 1].to_uint() << 8) |
    (bytes[offset + 2].to_uint() << 16) |
    (bytes[offset + 3].to_uint() << 24)
  let word = if little {
    word
  } else {
    (word >> 24) |
    ((word >> 8) & 0xff00U) |
    ((word << 8) & 0xff0000U) |
    (word << 24)
  }
  word.reinterpret_as_int()
}

///|
fn sparse_matrix_read(
  bytes : Bytes,
  outer : Element,
  little : Bool,
  limits : Limits,
  nested? : Bool = false,
  keep? : Bool = true,
  name_encoding? : NameEncoding = Utf8,
) -> (SparseArray?, Int) raise MatError {
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
  let text = decode_name(
    bytes[name.start:name.start + name.size],
    name_encoding,
    name.start,
  )
  validate_name(text, limits, allow_empty=nested, name_encoding~)
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
  let slots = ir.size / 4
  let rows = if keep {
    Array::makei(slots, i => csc_index_at(bytes, ir.start + i * 4, little))
  } else {
    []
  }
  let cols = if keep {
    Array::makei(jc.size / 4, i => csc_index_at(bytes, jc.start + i * 4, little))
  } else {
    []
  }
  let values = tag(bytes, jc.next, end, little)
  if dtype == Float64 && values.kind != 9 {
    fail(
      "unsupported-sparse-dtype",
      values.start,
      "Sparse numerical storage must be float64",
    )
  }
  let real = numeric_payload(bytes, values, dtype, slots, little, keep~)
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
      Some(numeric_payload(bytes, values, dtype, slots, little, keep~)),
      values.next,
    )
  } else {
    (None, values.next)
  }
  if next != end {
    fail("trailing-matrix-data", next, "Unexpected sparse matrix data")
  }
  if !keep {
    if capacity < slots.to_uint64() {
      fail("element-limit", 0, "Sparse capacity is smaller than stored slots")
    }
    let pointer = fn(i : Int) { csc_index_at(bytes, jc.start + i * 4, little) }
    if pointer(0) != 0 || pointer(shape[1]) > slots {
      fail(
        "invalid-sparse", 0, "CSC pointers must start at zero and fit stored slots",
      )
    }
    let index_bytes = ir.size + jc.size
    let payload_bytes = slots * dtype.width()
    if index_bytes > limits.max_file_bytes ||
      payload_bytes >
      (limits.max_file_bytes - index_bytes) / (if complex { 2 } else { 1 }) {
      fail("file-limit", 0, "Sparse payload exceeds byte limit")
    }
    for col = 0; col < shape[1]; col = col + 1 {
      let start = pointer(col)
      let end = pointer(col + 1)
      if start < 0 || end < start || end > slots {
        fail(
          "invalid-sparse", col, "CSC column pointers must be monotone and bounded",
        )
      }
      for i = start; i < end; i = i + 1 {
        let row = csc_index_at(bytes, ir.start + i * 4, little)
        if row < 0 || row >= shape[0] {
          fail("invalid-sparse", i, "Sparse row is outside dimensions")
        }
      }
    }
    return (None, slots)
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
  ignore(validate_sparse(result, limits, allow_empty=nested, name_encoding~))
  (Some(result), slots)
}

///|
fn sparse_matrix(
  bytes : Bytes,
  outer : Element,
  little : Bool,
  limits : Limits,
  nested? : Bool = false,
  name_encoding? : NameEncoding = Utf8,
) -> SparseArray raise MatError {
  let (value, _) = sparse_matrix_read(
    bytes,
    outer,
    little,
    limits,
    nested~,
    name_encoding~,
  )
  value.unwrap()
}
