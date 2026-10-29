///|
test "zlib rejects preset dictionaries reserved blocks and stored length mismatch" {
  assert_eq(
    error_code(() => ignore(inflate_zlib(b"\x78\x20\x00\x00\x00\x00"))),
    "unsupported-zlib",
  )
  assert_eq(
    error_code(() => ignore(inflate_zlib(b"\x78\x01\x07\x00\x00\x00\x01"))),
    "invalid-zlib",
  )
  assert_eq(
    error_code(() => {
      ignore(inflate_zlib(b"\x78\x01\x01\x01\x00\x00\x00\x41\x00\x42\x00\x42"))
    }),
    "invalid-zlib",
  )
}

///|
test "zlib exact expanded quota checksum and every truncation retain strict failures" {
  let source = @utf8.encode("x".repeat(513)[:])
  let compressed = deflate_zlib(source)
  assert_true(inflate_zlib(compressed, max_bytes=513) == source)
  assert_eq(
    error_code(() => ignore(inflate_zlib(compressed, max_bytes=512))),
    "expanded-limit",
  )
  for size = 0; size < compressed.length(); size = size + 1 {
    let prefix = Bytes::from_array(Array::makei(size, i => compressed[i]))
    assert_true(error_code(() => ignore(inflate_zlib(prefix))) != "no-error")
  }
  let damaged = FixedArray::makei(compressed.length(), i => compressed[i])
  damaged[damaged.length() - 1] = (damaged[damaged.length() - 1].to_int() ^ 1).to_byte()
  assert_eq(
    error_code(() => ignore(inflate_zlib(finish_owned_buffer(damaged)))),
    "invalid-zlib",
  )
}

///|
test "tree comparisons finish counting after the global sample budget" {
  let a = numeric_array("value", Float64, [1, 3], [
    Floating(1.0),
    Floating(2.0),
    Floating(3.0),
  ])
  let b = numeric_array("value", Float64, [1, 3], [
    Floating(4.0),
    Floating(5.0),
    Floating(6.0),
  ])
  let left : MatTree = {
    description: "",
    little_endian: true,
    variables: [Numeric(a)],
  }
  let right = { ..left, variables: [Numeric(b)], }
  let exact = compare_trees(left, right, max_samples=0)
  let close = compare_trees_close(left, right, max_samples=0)
  assert_true(
    !exact.content_equal && exact.samples.length() == 0 && exact.truncated,
  )
  assert_true(
    !close.within_tolerance && close.samples.length() == 0 && close.truncated,
  )
}
