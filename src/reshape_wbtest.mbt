///|
test "reshape keeps exact complex planes flags and independent dimensions" {
  let a = numeric_array("z", Float64, [2, 2], [Floating(-0.0), Floating(2.0), Floating(3.0), Floating(4.0)], imaginary=[Floating(5.0), Floating(6.0), Floating(7.0), Floating(8.0)], is_global=true)
  let shape = [1, 2, 2]
  let b = a.reshape(shape)
  shape[0] = 9
  assert_eq(b.shape, [1, 2, 2])
  assert_true(b.real == a.real && b.imag == a.imag && b.is_global)
  assert_eq(b.index([0, 1, 1]), 3)
  assert_eq(error_code(() => ignore(a.reshape([1, 3]))), "shape-mismatch")
  assert_eq(error_code(() => ignore(a.reshape([4]))), "invalid-shape")
}

///|
test "reshape preserves empty arrays and exact unsigned integers" {
  let empty = raw_array("empty", Int64, [0, 3], b"")
  assert_eq(empty.reshape([2, 0, 4]).length(), 0)
  let a = numeric_array("ids", UInt64, [2, 1], [Unsigned(9007199254740993UL), Unsigned(18446744073709551615UL)])
  let b = a.reshape([1, 2])
  assert_true(b.real == a.real)
  assert_true(read_mat(write_mat([b])).arrays[0].real == a.real)
}
