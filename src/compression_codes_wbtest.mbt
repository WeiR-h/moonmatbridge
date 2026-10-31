///|
test "fixed code boundary vectors and zlib framing match independent golden bytes" {
  for
    (symbol, code) in [
      (0, 524300),
      (143, 524541),
      (144, 589843),
      (255, 590335),
      (256, 458752),
      (279, 458868),
      (280, 524291),
      (287, 524515),
    ] {
    assert_eq(compression_literals[symbol], code)
  }
  for
    (symbol, code) in [
      (0, 0),
      (1, 16),
      (2, 8),
      (15, 30),
      (16, 1),
      (29, 23),
      (31, 31),
    ] {
    assert_eq(compression_distances[symbol], code)
  }
  let one = Bytes::from_array(
    [0x78, 0x01, 0x73, 0x04, 0x00, 0x00, 0x42, 0x00, 0x42].map(v => v.to_byte()),
  )
  assert_true(deflate_zlib(b"A") == one)
  assert_true(inflate_zlib(one) == b"A")
}
