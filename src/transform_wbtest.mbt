///|
test "strided three-dimensional slice preserves exact complex payloads" {
  let a = numeric_array(
    "signal",
    Float64,
    [3, 4, 2],
    Array::makei(24, i => Floating(i.to_double())),
    imaginary=Array::makei(24, i => Floating(-i.to_double())),
  )
  let b = a.slice([1, 0, 1], [2, 2, 1], steps=[1, 2, 1])
  assert_eq(b.shape, [2, 2, 1])
  for i, expected in [13, 14, 19, 20] {
    assert_true(b.value(i) is Floating(n) && n == expected.to_double())
    assert_true(
      b.value(i, imaginary=true) is Floating(n) && n == -expected.to_double(),
    )
  }
  assert_eq(
    error_code(() => ignore(a.slice([0, 0, 0], [4, 1, 1]))),
    "invalid-slice",
  )
  assert_eq(
    error_code(() => ignore(a.slice([0, 0, 0], [1, 1, 1], steps=[1, 0, 1]))),
    "invalid-slice",
  )
  assert_eq(error_code(() => ignore(a.slice([0], [1]))), "invalid-slice")
  assert_eq(a.slice([3, 0, 0], [0, 4, 2]).length(), 0)
}

///|
test "axis gather and concat retain integer bits ordering and empty arrays" {
  let a = numeric_array("ids", UInt64, [2, 3], [
    Unsigned(9007199254740993UL),
    Unsigned(2UL),
    Unsigned(3UL),
    Unsigned(4UL),
    Unsigned(5UL),
    Unsigned(18446744073709551615UL),
  ])
  let b = a.gather_axis(1, [2, 0, 2])
  assert_true(b.value(1) is Unsigned(18446744073709551615UL))
  assert_true(b.value(2) is Unsigned(9007199254740993UL))
  assert_true(b.real[0:16] == b.real[32:48])
  let c = concat_arrays(
    "joined",
    [a.slice([0, 0], [2, 1]), a.slice([0, 1], [2, 2])],
    1,
  )
  assert_true(c.real == a.real)
  let rows = concat_arrays(
    "rows",
    [a.slice([0, 0], [1, 3]), a.slice([1, 0], [1, 3])],
    0,
  )
  assert_true(rows.real == a.real)
  assert_eq(a.gather_axis(1, []).shape, [2, 0])
  assert_eq(error_code(() => ignore(a.gather_axis(1, [3]))), "index-range")
  assert_eq(error_code(() => ignore(a.gather_axis(2, []))), "invalid-axis")
  assert_eq(
    error_code(() => ignore(concat_arrays("x", [], 0))),
    "invalid-concat",
  )
}

///|
test "transform preserves NaN payload signed zero and rejects incompatible concat" {
  let a = raw_array(
    "bits",
    Float64,
    [2, 1],
    b"\x01\x00\x00\x00\x00\x00\xf8\x7f\x00\x00\x00\x00\x00\x00\x00\x80",
  )
  assert_true(a.gather_axis(0, [1, 0, 1]).real[8:16] == a.real[0:8])
  assert_true(a.slice([0, 0], [2, 1]).real == a.real)
  let mismatch = numeric_array("y", Int8, [2, 1], [Signed(1L), Signed(2L)])
  assert_eq(
    error_code(() => ignore(concat_arrays("x", [a, mismatch], 1))),
    "incompatible-array",
  )
  let limits = { ..default_limits(), max_elements: 2, }
  assert_eq(
    error_code(() => ignore(a.gather_axis(0, [0, 1, 0], limits~))),
    "element-limit",
  )
}
