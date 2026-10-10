///|
test "CSC mixed MAT roundtrips exact capacity planes and global flags" {
  let dense = numeric_array("dense", UInt64, [1, 1], [Unsigned(18446744073709551615UL)])
  let sparse = raw_sparse_array("s", Float64, [1000000, 3], [2, 999999, 9], [0, 1, 2, 2], b"\x01\x00\x00\x00\x00\x00\xf8\x7f\x00\x00\x00\x00\x00\x00\x00\x80\x00\x00\x00\x00\x00\x00\xf0\x3f", imag=Bytes::make(24, b'\x00'), nzmax=5, is_global=true)
  for compressed in [false, true] {
    let bytes = write_document([Dense(dense), Sparse(sparse)], compressed~)
    let file = read_document(bytes)
    assert_eq(file.variables.length(), 2)
    match file.get("s") {
      Some(Sparse(s)) => {
        assert_eq(s.shape, [1000000, 3])
        assert_eq(s.nzmax, 5)
        assert_eq(s.nnz(), 2)
        assert_true(s.real == sparse.real && s.imag == sparse.imag && s.is_global)
        assert_eq(s.row_indices, sparse.row_indices)
        assert_eq(s.col_ptrs, sparse.col_ptrs)
      }
      _ => assert_true(false)
    }
    assert_eq(error_code(() => ignore(read_mat(bytes))), "unsupported-class")
    assert_eq(read_document(write_document(file.select(["s"]))).variables.length(), 1)
  }
}

///|
test "CSC densification is explicit bounded and preserves negative zero NaN and complex bits" {
  let a = raw_array("x", Float64, [2, 2], b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x80\x01\x00\x00\x00\x00\x00\xf8\x7f\x00\x00\x00\x00\x00\x00\x00\x00", imag=Bytes::make(32, b'\x00'))
  let s = a.to_sparse()
  assert_eq(s.nnz(), 2)
  assert_true(s.to_dense().real == a.real && s.to_dense().imag == a.imag)
  let huge = raw_sparse_array("huge", Float64, [1000000, 1000], [999999], Array::makei(1001, i => if i == 0 { 0 } else { 1 }), b"\x00\x00\x00\x00\x00\x00\xf0\x3f")
  assert_true(write_document([Sparse(huge)]).length() < 5000)
  assert_eq(error_code(() => ignore(huge.to_dense())), "element-limit")
  let empty = raw_sparse_array("e", Logical, [0, 3], [], [0, 0, 0, 0], b"")
  assert_eq(empty.to_dense().shape, [0, 3])
}

///|
test "CSC validates pointers indices ordering storage and numeric types" {
  let make = (rows : Array[Int], cols : Array[Int]) => ignore(raw_sparse_array("x", Float64, [2, 2], rows, cols, Bytes::make(rows.length() * 8, b'\x00')))
  assert_eq(error_code(() => make([0], [0, 2, 1])), "invalid-sparse")
  assert_eq(error_code(() => make([2], [0, 1, 1])), "invalid-sparse")
  assert_eq(error_code(() => make([1, 0], [0, 2, 2])), "noncanonical-sparse")
  assert_eq(error_code(() => make([0, 0], [0, 2, 2])), "noncanonical-sparse")
  assert_eq(error_code(() => ignore(raw_sparse_array("x", Int64, [1, 1], [0], [0, 1], Bytes::make(8, b'\x00')))), "unsupported-sparse-dtype")
  assert_eq(error_code(() => ignore(raw_sparse_array("x", Logical, [1, 1], [0], [0, 1], b"\x02"))), "invalid-logical")
}
