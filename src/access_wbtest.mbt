///|
test "scalar access rejects publicly constructed invalid layouts" {
  let short : NumericArray = { name: "x", dtype: Float64, shape: [1, 2], real: b"\x00\x00\x00\x00\x00\x00\x00\x00", imag: None, is_global: false }
  assert_eq(error_code(() => ignore(short.value(0))), "payload-size")
  let complex : NumericArray = { name: "z", dtype: Float64, shape: [1, 1], real: short.real, imag: Some(b""), is_global: false }
  assert_eq(error_code(() => ignore(complex.value(0, imaginary=true))), "payload-size")
  let logical : NumericArray = { name: "b", dtype: Logical, shape: [1, 1], real: b"\x02", imag: None, is_global: false }
  assert_eq(error_code(() => ignore(logical.value(0))), "invalid-logical")
  let valid = numeric_array("a", Int8, [1, 1], [Signed(7L)])
  assert_eq(error_code(() => ignore(valid.value(1))), "index-range")
  assert_eq(error_code(() => ignore(valid.value(-1))), "index-range")
}
