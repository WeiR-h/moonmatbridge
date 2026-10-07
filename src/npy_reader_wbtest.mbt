///|
fn test_npy(header : String, data : Bytes, major : Int) -> Bytes {
  let prefix = if major == 1 { 10 } else { 12 }
  let body = @utf8.encode(header[:])
  let padding = (64 - (prefix + body.length() + 1) % 64) % 64
  let out = b"\x93NUMPY".to_array()
  out.push(major.to_byte())
  out.push(b'\x00')
  push_bits(out, (body.length() + padding + 1).to_uint64(), prefix - 8)
  for byte in body { out.push(byte) }
  for _i = 0; _i < padding; _i = _i + 1 { out.push(b' ') }
  out.push(b'\n')
  for byte in data { out.push(byte) }
  Bytes::from_array(out)
}

///|
test "numeric NPY reader restores exact C and Fortran arrays in three versions" {
  let a = numeric_array("x", UInt64, [2, 3], [Unsigned(9007199254740993UL), Unsigned(2UL), Unsigned(3UL), Unsigned(4UL), Unsigned(5UL), Unsigned(18446744073709551615UL)])
  let roundtrip = read_npy(write_npy(a), "copy")
  assert_true(roundtrip.real == a.real && roundtrip.shape == a.shape && roundtrip.name == "copy")
  for major in [1, 2, 3] {
    let data = numeric_array("c", UInt64, [1, 6], [Unsigned(9007199254740993UL), Unsigned(3UL), Unsigned(5UL), Unsigned(2UL), Unsigned(4UL), Unsigned(18446744073709551615UL)]).real
    let file = test_npy("{'shape': (2, 3), 'fortran_order': False, 'descr': '<u8'}", data, major)
    assert_true(read_npy(file, "c").real == a.real)
  }
}

///|
test "NPY complex big endian scalar vector and empty shapes" {
  let complex = test_npy("{'descr': '>c8', 'shape': (1,), 'fortran_order': False}", b"\x3f\x80\x00\x00\xc0\x00\x00\x00", 1)
  let restored = read_npy(complex, "z")
  assert_eq(restored.shape, [1, 1])
  assert_true(restored.real == b"\x00\x00\x80\x3f" && restored.imag == Some(b"\x00\x00\x00\xc0"))
  let scalar = test_npy("{'descr': '|b1', 'shape': (), 'fortran_order': True}", b"\x03", 2)
  assert_true(read_npy(scalar, "b").real == b"\x01")
  let empty = test_npy("{'descr': '<i8', 'shape': (0,), 'fortran_order': False}", b"", 3)
  assert_eq(read_npy(empty, "e").shape, [0, 1])
}

///|
test "NPY reader rejects pickle descriptors invalid headers and all truncations" {
  let object = test_npy("{'descr': '|O', 'shape': (1,), 'fortran_order': False}", b"", 1)
  assert_eq(error_code(() => ignore(read_npy(object, "x"))), "unsupported-npy-dtype")
  let duplicate = test_npy("{'descr': '|i1', 'shape': (1,), 'shape': (1,), 'fortran_order': True}", b"\x01", 1)
  assert_eq(error_code(() => ignore(read_npy(duplicate, "x"))), "invalid-npy")
  let expression = test_npy("{'descr': '|i1', 'shape': (1+2,), 'fortran_order': True}", b"\x01", 1)
  assert_eq(error_code(() => ignore(read_npy(expression, "x"))), "invalid-npy")
  let valid = write_npy(numeric_array("x", Int8, [1, 1], [Signed(7L)]))
  for n = 0; n < valid.length(); n = n + 1 {
    assert_true(error_code(() => ignore(read_npy(valid[0:n].to_owned(), "x"))) != "no-error")
  }
  assert_eq(error_code(() => ignore(read_npy(valid + b"\x00", "x"))), "payload-size")
}
