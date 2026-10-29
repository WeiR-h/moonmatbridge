///|
test "compressed sink chooses stored coding for fixed-seed incompressible blocks" {
  let buffer = FixedArray::make(150000, b'\x00')
  let mut seed : UInt32 = 20261029U
  for i = 0; i < buffer.length(); i = i + 1 {
    seed = seed * 1664525U + 1013904223U
    buffer[i] = (seed >> 24).to_byte()
  }
  let node = Numeric(
    raw_array("noise", UInt8, [1, buffer.length()], finish_owned_buffer(buffer)),
  )
  let bytes = compressed_sink_capture([node], 16381, 7)
  assert_eq((bytes[138].to_int() >> 1) & 3, 0)
  assert_true(compressed_sink_capture([node], 1048576, 1048576) == bytes)
  let bad = FixedArray::makei(bytes.length(), i => bytes[i])
  bad[bad.length() - 1] = (bad[bad.length() - 1].to_int() ^ 1).to_byte()
  assert_eq(
    error_code(() => ignore(read_selected(finish_owned_buffer(bad), []))),
    "invalid-zlib",
  )
}
