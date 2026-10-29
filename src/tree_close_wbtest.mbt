///|
fn close_tree(
  values : Array[Double],
  dtype~ : DType = Float64,
) -> MatTree raise MatError {
  let a = numeric_array(
    "values",
    dtype,
    [1, values.length()],
    values.map(v => Floating(v)),
  )
  { description: "", little_endian: true, variables: [Numeric(a)], }
}

///|
test "tree close is symmetric at exact absolute and relative boundaries" {
  let a = close_tree([1.0, 0.0, -2.0])
  let b = close_tree([1.25, 0.25, -2.25])
  let report = compare_trees_close(a, b, atol=0.25)
  assert_true(!report.exact_equal && report.within_tolerance)
  assert_eq(report.differences, 0)
  assert_true(compare_trees_close(b, a, atol=0.25).within_tolerance)
  assert_eq(compare_trees_close(a, b, atol=0.249, max_samples=1).differences, 3)
  assert_true(
    compare_trees_close(close_tree([1.0]), close_tree([2.0]), rtol=0.5).within_tolerance,
  )
  assert_true(
    !compare_trees_close(close_tree([1.0]), close_tree([2.0]), rtol=0.499).within_tolerance,
  )
  assert_true(
    compare_trees_close(close_tree([1.0e308]), close_tree([-1.0e308]), rtol=2.0).within_tolerance,
  )
  assert_true(
    !compare_trees_close(
      close_tree([1.0e308]),
      close_tree([-1.0e308]),
      atol=1.7e308,
    ).within_tolerance,
  )
  assert_true(
    compare_trees_close(
      close_tree([1.0e308]),
      close_tree([-1.0e308]),
      atol=1.7e308,
      rtol=0.31,
    ).within_tolerance,
  )
  assert_true(
    !compare_trees_close(
      close_tree([1.0e308]),
      close_tree([-1.0e308]),
      atol=1.7e308,
      rtol=0.29,
    ).within_tolerance,
  )
  assert_true(
    !compare_trees_close(close_tree([0.0]), close_tree([5.0e-324])).within_tolerance,
  )
  assert_true(
    compare_trees_close(
      close_tree([0.0]),
      close_tree([5.0e-324]),
      atol=5.0e-324,
    ).within_tolerance,
  )
}

///|
test "tree close preserves exact flags and explicit nonfinite semantics" {
  let negative = diff_fixture(b"\x00\x00\x00\x00\x00\x00\x00\x80")
  let positive = diff_fixture(b"\x00\x00\x00\x00\x00\x00\x00\x00")
  let zero = compare_trees_close(negative, positive)
  assert_true(zero.within_tolerance && !zero.exact_equal)
  let nan = diff_fixture(b"\x01\x00\x00\x00\x00\x00\xf8\x7f")
  let result = compare_trees_close(nan, nan, max_samples=0)
  assert_true(
    result.exact_equal && !result.within_tolerance && result.truncated,
  )
  assert_eq(result.differences, 1)
  assert_true(compare_trees_close(nan, nan, equal_nan=true).within_tolerance)
  let other = diff_fixture(b"\x02\x00\x00\x00\x00\x00\xf8\x7f")
  assert_true(!compare_trees_close(nan, other, equal_nan=true).exact_equal)
  assert_true(
    compare_trees_close(close_tree([1.0 / 0.0]), close_tree([1.0 / 0.0])).within_tolerance,
  )
  assert_true(
    !compare_trees_close(
      close_tree([1.0 / 0.0]),
      close_tree([-1.0 / 0.0]),
      atol=1.0e308,
    ).within_tolerance,
  )
  assert_true(
    !compare_trees_close(
      close_tree([1.0 / 0.0]),
      close_tree([1.0e308]),
      rtol=1.0e308,
    ).within_tolerance,
  )
  for bad in [-1.0, 1.0 / 0.0, 0.0 / 0.0] {
    assert_eq(
      error_code(() => ignore(compare_trees_close(positive, positive, atol=bad))),
      "invalid-limits",
    )
    assert_eq(
      error_code(() => ignore(compare_trees_close(positive, positive, rtol=bad))),
      "invalid-limits",
    )
  }
}

///|
test "tree close keeps integer and metadata comparison exact and samples global" {
  let a = close_tree([1.0, 2.0, 3.0])
  let b = close_tree([2.0, 3.0, 4.0])
  let report = compare_trees_close(a, b, max_samples=1)
  assert_eq(report.differences, 3)
  assert_eq(report.samples.length(), 1)
  assert_true(report.truncated && !report.within_tolerance)
  let x = raw_array("x", UInt64, [1, 1], b"\xff\xff\xff\xff\xff\xff\xff\xff")
  let y = { ..x, real: b"\xfe\xff\xff\xff\xff\xff\xff\xff", }
  assert_true(
    !compare_trees_close(
      { ..a, variables: [Numeric(x)], },
      { ..a, variables: [Numeric(y)], },
      atol=1.0e308,
    ).within_tolerance,
  )
  let f = close_tree([1.0], dtype=Float32)
  let g = close_tree([1.125], dtype=Float32)
  assert_true(compare_trees_close(f, g, atol=0.125).within_tolerance)
}

///|
test "tree close compares complex planes and storage metadata independently" {
  let a = numeric_array("wave", Float64, [1, 1], [Floating(1.0)], imaginary=[
    Floating(2.0),
  ])
  let b = {
    ..a,
    imag: Some(numeric_array("tmp", Float64, [1, 1], [Floating(2.125)]).real),
  }
  let left : MatTree = {
    description: "",
    little_endian: true,
    variables: [Numeric(a)],
  }
  let right = { ..left, variables: [Numeric(b)], }
  assert_true(compare_trees_close(left, right, atol=0.125).within_tolerance)
  assert_eq(compare_trees_close(left, right).samples[0].kind, "imag")
  let global = { ..left, variables: [Numeric({ ..a, is_global: true, })], }
  assert_true(!compare_trees_close(left, global, atol=1.0e308).within_tolerance)
  let s = raw_sparse_array(
    "s",
    Float64,
    [2, 1],
    [1, 0],
    [0, 2],
    a.real + a.real,
    nzmax=3,
  )
  let t = { ..s, row_indices: [0, 1], }
  assert_true(
    !compare_trees_close(
      { ..left, variables: [Csc(s)], },
      { ..left, variables: [Csc(t)], },
      atol=1.0e308,
    ).within_tolerance,
  )
  let t = { ..s, nzmax: 4, }
  assert_eq(
    compare_trees_close({ ..left, variables: [Csc(s)], }, {
      ..left,
      variables: [Csc(t)],
    }).samples[0].kind,
    "nzmax",
  )
  let c = utf8_char_array("label", [1, 1], "a")
  let d = { ..c, data: b"b", }
  assert_true(
    !compare_trees_close(
      { ..left, variables: [Character(c)], },
      { ..left, variables: [Character(d)], },
      atol=1.0e308,
    ).within_tolerance,
  )
  assert_eq(
    error_code(() => ignore(compare_trees_close(left, right, max_samples=257))),
    "invalid-limits",
  )
}

///|
test "tree close reports root order as exact metadata without changing exact API" {
  let a = Numeric(numeric_array("one", Float64, [1, 1], [Floating(1.0)]))
  let b = Numeric(numeric_array("two", Float64, [1, 1], [Floating(2.0)]))
  let left : MatTree = {
    description: "",
    little_endian: true,
    variables: [a, b],
  }
  let right = { ..left, variables: [b, a], }
  assert_true(compare_trees(left, right).content_equal)
  let report = compare_trees_close(left, right)
  assert_true(
    report.variable_order_changed &&
    !report.exact_equal &&
    !report.within_tolerance,
  )
  assert_eq(report.differences, 1)
  assert_eq(report.samples[0].path, [])
  assert_eq(report.samples[0].kind, "root_order")
}
