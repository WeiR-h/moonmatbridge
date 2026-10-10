///|
fn sparse_matrix(bytes : Bytes, outer : Element, little : Bool, limits : Limits) -> SparseArray raise MatError {
  let end = outer.start + outer.size
  let flags = tag(bytes, outer.start, end, little)
  if flags.kind != 6 || flags.size != 8 { fail("invalid-flags", outer.start, "Expected sparse miUINT32 flags") }
  let bits = bits_at(bytes, flags.start, 4, little).to_uint()
  if (bits & 255U) != 5U || (bits & 0xfffff100U) != 0U { fail("unsupported-flags", flags.start, "Unknown sparse flags") }
  let capacity = bits_at(bytes, flags.start + 4, 4, little)
  if capacity > limits.max_elements.to_uint64() { fail("element-limit", flags.start, "Sparse nzmax exceeds limit") }
  let dtype = if (bits & 512U) != 0U { Logical } else { Float64 }
  let complex = (bits & 2048U) != 0U
  if complex && dtype == Logical { fail("unsupported-complex", flags.start, "Logical sparse cannot be complex") }
  let dims = tag(bytes, flags.next, end, little)
  if dims.kind != 5 || dims.size != 8 { fail("invalid-shape", dims.start, "Sparse matrices need two dimensions") }
  let shape = Array::makei(2, i => bits_at(bytes, dims.start + i * 4, 4, little).to_uint().reinterpret_as_int())
  if shape[0] < 0 || shape[1] < 0 || shape[1] >= limits.max_elements { fail("invalid-shape", dims.start, "Sparse dimensions or column pointers exceed bounds") }
  let name = tag(bytes, dims.next, end, little)
  if name.kind != 1 || name.size == 0 || name.size > limits.max_name_bytes { fail("invalid-name", name.start, "Expected bounded sparse variable name") }
  let text = @utf8.decode(bytes[name.start:name.start + name.size]) catch { _ => { fail("invalid-name", name.start, "Sparse name must be UTF-8"); "" } }
  let ir = tag(bytes, name.next, end, little)
  let jc = tag(bytes, ir.next, end, little)
  if ir.kind != 5 || ir.size % 4 != 0 || ir.size / 4 > limits.max_elements || jc.kind != 5 || jc.size != (shape[1] + 1) * 4 {
    fail("invalid-sparse", ir.start, "Expected bounded miINT32 CSC row indices and column pointers")
  }
  let rows = Array::makei(ir.size / 4, i => bits_at(bytes, ir.start + i * 4, 4, little).to_uint().reinterpret_as_int())
  let cols = Array::makei(jc.size / 4, i => bits_at(bytes, jc.start + i * 4, 4, little).to_uint().reinterpret_as_int())
  let values = tag(bytes, jc.next, end, little)
  if dtype == Float64 && values.kind != 9 { fail("unsupported-sparse-dtype", values.start, "Sparse numerical storage must be float64") }
  let real = numeric_payload(bytes, values, dtype, rows.length(), little)
  let (imag, next) = if complex {
    let values = tag(bytes, values.next, end, little)
    if values.kind != 9 { fail("unsupported-sparse-dtype", values.start, "Sparse imaginary storage must be float64") }
    (Some(numeric_payload(bytes, values, dtype, rows.length(), little)), values.next)
  } else { (None, values.next) }
  if next != end { fail("trailing-matrix-data", next, "Unexpected sparse matrix data") }
  raw_sparse_array(text, dtype, shape, rows, cols, real, imag?, nzmax=capacity.to_int(), is_global=(bits & 1024U) != 0U, limits~)
}

///|
fn encoded_sparse(a : SparseArray) -> Bytes {
  let out = []
  let flags = []
  push_bits(flags, (5 + (if a.dtype == Logical { 512 } else { 0 }) + (if a.is_global { 1024 } else { 0 }) + (if a.imag is Some(_) { 2048 } else { 0 })).to_uint64(), 4)
  push_bits(flags, a.nzmax.to_uint64(), 4)
  append_element(out, 6, Bytes::from_array(flags))
  let dims = []
  for dim in a.shape { push_bits(dims, dim.to_uint64(), 4) }
  append_element(out, 5, Bytes::from_array(dims))
  append_element(out, 1, @utf8.encode(a.name[:]))
  let rows = []
  for row in a.row_indices { push_bits(rows, row.reinterpret_as_uint().to_uint64(), 4) }
  append_element(out, 5, Bytes::from_array(rows))
  let cols = []
  for col in a.col_ptrs { push_bits(cols, col.to_uint64(), 4) }
  append_element(out, 5, Bytes::from_array(cols))
  append_element(out, a.dtype.mi_type(), a.real)
  if a.imag is Some(imag) { append_element(out, a.dtype.mi_type(), imag) }
  Bytes::from_array(out)
}
