///|
test "axis permutation transposes exact uint64 data and is invertible" {
  let a = numeric_array("x", UInt64, [2, 3], [Unsigned(9007199254740993UL), Unsigned(2UL), Unsigned(3UL), Unsigned(4UL), Unsigned(5UL), Unsigned(18446744073709551615UL)])
  let b = a.permute_axes([1, 0])
  assert_eq(b.shape, [3, 2])
  let expected = numeric_array("x", UInt64, [3, 2], [Unsigned(9007199254740993UL), Unsigned(3UL), Unsigned(5UL), Unsigned(2UL), Unsigned(4UL), Unsigned(18446744073709551615UL)])
  assert_true(b.real == expected.real)
  assert_true(b.permute_axes([1, 0]).real == a.real)
  assert_eq(error_code(() => ignore(a.permute_axes([0, 0]))), "invalid-axes")
  assert_eq(error_code(() => ignore(a.permute_axes([0, 2]))), "invalid-axes")
  assert_eq(error_code(() => ignore(a.permute_axes([0]))), "invalid-axes")
}

///|
test "three dimensional complex permutations preserve raw planes and empty shape" {
  let a = numeric_array("z", Float64, [2, 2, 2], Array::makei(8, fn(i) { Floating(i.to_double()) }), imaginary=Array::makei(8, fn(i) { Floating(-i.to_double()) }), is_global=true)
  let b = a.permute_axes([2, 0, 1])
  let c = b.permute_axes([1, 2, 0])
  assert_true(c.real == a.real && c.imag == a.imag && c.shape == a.shape && c.is_global)
  let empty = raw_array("e", Int8, [0, 3, 2], b"")
  assert_eq(empty.permute_axes([2, 0, 1]).shape, [2, 0, 3])
}
