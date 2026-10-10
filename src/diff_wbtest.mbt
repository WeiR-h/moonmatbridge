///|
test "diff ignores MAT encoding and variable order while reporting exact float and integer changes" {
  let bits = raw_array(
    "bits",
    Float64,
    [2, 1],
    b"\x42\x00\x00\x00\x00\x00\xf8\x7f\x00\x00\x00\x00\x00\x00\x00\x80",
    imag=Bytes::make(16, b'\x00'),
  )
  let ids = numeric_array("ids", UInt64, [1, 1], [
    Unsigned(18446744073709551615UL),
  ])
  let first = read_document(write_mat([bits, ids]))
  let other = read_document(write_mat([ids, bits], compressed=true))
  let equal = compare_documents(first, other)
  assert_true(equal.content_equal && equal.variable_order_changed)
  let changed = raw_array(
    "bits",
    Float64,
    [2, 1],
    b"\x43\x00\x00\x00\x00\x00\xf8\x7f\x00\x00\x00\x00\x00\x00\x00\x00",
    imag=b"\x00\x00\x00\x00\x00\x00\x00\x80\x00\x00\x00\x00\x00\x00\x00\x00",
  )
  let changed_ids = numeric_array("ids", UInt64, [1, 1], [
    Unsigned(18446744073709551614UL),
  ])
  let report = compare_documents(
    first,
    read_document(write_mat([changed, changed_ids])),
    max_samples=2,
  )
  assert_true(!report.content_equal)
  assert_eq(report.changed_variables, 2)
  assert_eq(report.variables[0].real_differences, 2)
  assert_eq(report.variables[0].imag_differences, 1)
  assert_eq(report.variables[0].samples[1].coordinates, [1, 0])
  assert_true(report.variables[0].truncated && report.variables[1].truncated)
  assert_eq(report.variables[1].real_differences, 1)
  assert_eq(report.variables[1].samples.length(), 0)
}

///|
test "diff covers added removed shape dtype flags and sparse storage metadata" {
  let x = raw_array("x", Float64, [1, 1], Bytes::make(8, b'\x00'))
  let y = raw_array("y", Float32, [1, 1], Bytes::make(4, b'\x00'))
  let a = read_document(write_mat([x]))
  let b = read_document(write_mat([y]))
  let result = compare_documents(a, b)
  assert_eq(result.changed_variables, 2)
  assert_eq(result.variables[0].status, "removed")
  assert_eq(result.variables[1].status, "added")
  let different = numeric_array(
    "x",
    Int64,
    [1, 2],
    [Signed(0L), Signed(0L)],
    is_global=true,
  )
  let meta = compare_documents(a, read_document(write_mat([different])))
  assert_true(
    meta.variables[0].metadata.contains("dtype") &&
    meta.variables[0].metadata.contains("shape") &&
    meta.variables[0].metadata.contains("global"),
  )
  assert_true(
    !compare_documents(
      a,
      read_document(write_document([Sparse(x.to_sparse())])),
    ).content_equal,
  )
  assert_eq(
    error_code(() => ignore(compare_documents(a, a, max_samples=-1))),
    "invalid-limits",
  )
}

///|
test "diff reports active CSC coordinates inactive capacity and pointer changes without densifying" {
  let a = raw_sparse_array(
    "s",
    Float64,
    [1000000, 3],
    [999999, 2],
    [0, 0, 1, 1],
    Bytes::make(16, b'\x00'),
    nzmax=3,
  )
  let b = {
    ..a,
    real: b"\x00\x00\x00\x00\x00\x00\xf0\x3f\x00\x00\x00\x00\x00\x00\xf0\x3f",
  }
  let report = compare_documents(
    read_document(write_document([Sparse(a)])),
    read_document(write_document([Sparse(b)])),
  )
  assert_eq(report.variables[0].real_differences, 2)
  assert_eq(report.variables[0].samples[0].coordinates, [999999, 1])
  assert_eq(report.variables[0].samples[1].coordinates, [])
  let changed = { ..a, col_ptrs: [0, 1, 1, 1], nzmax: 4, }
  let metadata = compare_documents(
    read_document(write_document([Sparse(a)])),
    read_document(write_document([Sparse(changed)])),
  )
  assert_true(
    metadata.variables[0].metadata.contains("col_ptrs") &&
    metadata.variables[0].metadata.contains("nzmax"),
  )
}
