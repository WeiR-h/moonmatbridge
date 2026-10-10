///|
test "deterministic compressor roundtrips empty repetitive binary and multiple stored blocks" {
  for input in [b"", b"hello hello hello", Bytes::make(120000, b'\x00'), Bytes::makei(140000, i => ((i * 31 + i / 7) & 255).to_byte())] {
    let encoded = deflate_zlib(input)
    assert_true(inflate_zlib(encoded) == input)
    assert_true(encoded == deflate_zlib(input))
  }
  assert_true(deflate_zlib(Bytes::make(100000, b'\x00')).length() < 1000)
  let stored = stored_zlib(Bytes::makei(140000, i => (i & 255).to_byte()), 150000)
  assert_true(inflate_zlib(stored) == Bytes::makei(140000, i => (i & 255).to_byte()))
  assert_eq(error_code(() => ignore(deflate_zlib(b"hello", max_bytes=6))), "file-limit")
  assert_eq(error_code(() => ignore(deflate_zlib(b"", max_bytes=-1))), "invalid-limits")
}

///|
test "compressed MAT writer preserves multiple variables exact bits and repeatability" {
  let a = raw_array("bits", Float64, [2, 1], b"\x01\x00\x00\x00\x00\x00\xf8\x7f\x00\x00\x00\x00\x00\x00\x00\x80")
  let b = numeric_array("ids", UInt64, [1, 2], [Unsigned(9007199254740993UL), Unsigned(18446744073709551615UL)])
  let bytes = write_mat([a, b], compressed=true)
  assert_true(bytes == write_mat([a, b], compressed=true))
  let file = read_mat(bytes)
  assert_true(file.arrays[0].real == a.real && file.arrays[1].real == b.real)
  let repetitive = raw_array("zeros", Float64, [100, 100], Bytes::make(80000, b'\x00'))
  assert_true(write_mat([repetitive], compressed=true).length() < write_mat([repetitive]).length() / 20)
}
