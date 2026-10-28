///|
test "buffered Huffman decode handles long codes and short final prefixes" {
  let long = huffman([10, 10], 0)
  let reader : BitReader = {
    bytes: b"\x00\x02",
    end: 2,
    position: 0,
    buffer: 0,
    available: 0,
  }
  assert_eq(long.decode(reader), 1)
  let short = huffman([1, 1], 0)
  let reader : BitReader = {
    bytes: b"\x01",
    end: 1,
    position: 0,
    buffer: 0,
    available: 0,
  }
  assert_eq(short.decode(reader), 1)
  reader.align()
  assert_eq(reader.position - reader.available / 8, 1)
}

///|
test "compressed windows exclude adjacent bytes and enforce exact stream endings" {
  let good = b"\x78\x9c\xcb\x48\xcd\xc9\xc9\x57\xc8\x40\x90\x00\x3a\x2e\x06\x7d"
  let wrapped = b"outside" + good + b"trailer"
  assert_true(
    inflate_window(wrapped, 7, good.length(), 17, None) == b"hello hello hello",
  )
  assert_eq(
    error_code(() => {
      ignore(inflate_window(wrapped, -1, good.length(), 17, None))
    }),
    "invalid-zlib",
  )
  let extra = Bytes::makei(good.length() + 1, i => {
    if i < good.length() - 4 {
      good[i]
    } else if i == good.length() - 4 {
      b'\x00'
    } else {
      good[i - 1]
    }
  })
  assert_eq(error_code(() => ignore(inflate_zlib(extra))), "invalid-zlib")
  let empty = deflate_zlib(b"")
  assert_true(inflate_zlib(empty, max_bytes=0) == b"")
}

///|
test "unselected compressed roots retain checksum and cumulative expansion validation" {
  let one = Numeric(numeric_array("one", Float64, [1, 1], [Floating(1.0)]))
  let two = Numeric(
    numeric_array("two", UInt8, [1, 3], [
      Unsigned(1UL),
      Unsigned(2UL),
      Unsigned(3UL),
    ]),
  )
  let encoded = write_tree([one, two], compressed=true)
  let first = tag(encoded, 128, encoded.length(), true)
  let second = tag(encoded, first.next, encoded.length(), true)
  let damaged = changed(encoded, second.start + second.size - 1, b'\xff')
  assert_eq(
    error_code(() => ignore(read_selected(damaged, ["one"]))),
    "invalid-zlib",
  )
  assert_eq(error_code(() => ignore(inspect_roots(damaged))), "invalid-zlib")
  assert_eq(error_code(() => ignore(read_tree(damaged))), "invalid-zlib")
  let first_size = inflate_window(
    encoded,
    first.start,
    first.size,
    4096,
    Some(true),
  ).length()
  let limits : Limits = { ..default_limits(), max_expanded_bytes: first_size, }
  assert_eq(
    error_code(() => ignore(read_selected(encoded, ["one"], limits~))),
    "expanded-limit",
  )
}

///|
test "bit prefetch survives fixed Huffman to stored flush block transitions" {
  // Independently produced by Node zlib with Z_SYNC_FLUSH between two writes.
  let encoded = b"\x78\x9c\x4a\x4c\x4a\x4e\x04\x23\x00\x00\x00\x00\xff\xff\x8b\x88\x8c\x8a\x88\x8c\x02\x00\x2d\x38\x05\x89"
  assert_true(inflate_zlib(encoded) == b"abcabcabcXYZXYZ")
  for end = 0; end < encoded.length(); end = end + 1 {
    let short = Bytes::makei(end, i => encoded[i])
    assert_eq(error_code(() => ignore(inflate_zlib(short))), "invalid-zlib")
  }
}

///|
test "optimized decode retains declared zlib window distance checks" {
  let prefix = Bytes::makei(300, i => ((i * 73 + i / 17 * 19) & 255).to_byte())
  let raw = prefix + prefix + prefix
  let encoded = deflate_zlib(raw)
  assert_true(inflate_zlib(encoded) == raw)
  // CMF 0x08 declares a 256-byte window; FCHECK 0x1d validates the header.
  let small_window = changed(changed(encoded, 0, b'\x08'), 1, b'\x1d')
  assert_eq(
    error_code(() => ignore(inflate_zlib(small_window))),
    "invalid-zlib",
  )
}
