///|
test "select extracts variables in caller order with exact raw payloads" {
  let a = numeric_array("a", UInt64, [1, 1], [Unsigned(9007199254740993UL)])
  let b = numeric_array("b", Float32, [1, 1], [Floating(-0.0)], imaginary=[
    Floating(2.0),
  ])
  let file = read_mat(write_mat([a, b]))
  let subset = file.select(["b", "a"])
  assert_true(
    subset[0].real == b.real &&
    subset[0].imag == b.imag &&
    subset[1].real == a.real,
  )
  assert_eq(file.select([]).length(), 0)
  assert_eq(
    error_code(() => ignore(file.select(["absent"]))),
    "missing-variable",
  )
  assert_eq(error_code(() => ignore(file.select(["a", "a"]))), "duplicate-name")
  let ambiguous : MatFile = {
    description: "",
    little_endian: true,
    arrays: [a, a],
  }
  assert_eq(error_code(() => ignore(ambiguous.select(["a"]))), "duplicate-name")
}
