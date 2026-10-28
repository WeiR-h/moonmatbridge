///|
fn source_inflate_test(
  bytes : Bytes,
  maximum : Int,
  chunk : Int,
) -> Bytes raise MatError {
  let cursor : SourceCursor = {
    source: test_source(bytes, 3),
    producer: None,
    buffer: FixedArray::make(chunk, b'\x00'),
    position: 0,
    start: 0,
    available: 0,
  }
  let inflater = make_source_inflater(cursor, bytes.length(), maximum)
  let out : Array[Byte] = []
  while true {
    match inflater.next() {
      Some(b) => out.push(b)
      None => break
    }
  }
  Bytes::from_array(out)
}

///|
test "incremental inflate crosses stored flush and Huffman boundaries with short reads" {
  let encoded = b"\x78\x9c\x4a\x4c\x4a\x4e\x04\x23\x00\x00\x00\x00\xff\xff\x8b\x88\x8c\x8a\x88\x8c\x02\x00\x2d\x38\x05\x89"
  for chunk in [1, 3, 7, 31] {
    assert_true(source_inflate_test(encoded, 15, chunk) == b"abcabcabcXYZXYZ")
  }
  for end = 0; end < encoded.length(); end = end + 1 {
    let short = Bytes::makei(end, i => encoded[i])
    assert_true(
      error_code(() => ignore(source_inflate_test(short, 15, 3))) != "no-error",
    )
  }
  assert_eq(
    error_code(() => ignore(source_inflate_test(encoded, 14, 3))),
    "expanded-limit",
  )
  let bad = changed(encoded, encoded.length() - 1, b'\x00')
  assert_eq(
    error_code(() => ignore(source_inflate_test(bad, 15, 1))),
    "invalid-zlib",
  )
}

///|
test "incremental inflate retains circular history declared windows and cumulative quotas" {
  let raw = Bytes::makei(200000, i => ((i * 73 + i / 17 * 19) & 255).to_byte())
  let encoded = deflate_zlib(raw)
  assert_true(source_inflate_test(encoded, raw.length(), 257) == raw)
  let window = changed(changed(encoded, 0, b'\x08'), 1, b'\x1d')
  assert_eq(
    error_code(() => ignore(source_inflate_test(window, raw.length(), 3))),
    "invalid-zlib",
  )
  let bytes = write_tree(mixed_tree(), compressed=true)
  assert_eq(
    error_code(() => {
      ignore(
        read_selected_from(test_source(bytes, 3), [], limits={
          ..default_source_limits(),
          max_expanded_bytes: 128,
          chunk_bytes: 7,
        }),
      )
    }),
    "expanded-limit",
  )
  assert_eq(
    read_selected_from(test_source(bytes, 3), [], limits={
      ..default_source_limits(),
      max_buffered_root_bytes: 128,
      chunk_bytes: 7,
    }).variables.length(),
    0,
  )
}

///|
test "buffered checksum covers partial final blocks and rejects extra expanded bytes" {
  assert_true(source_inflate_test(deflate_zlib(b""), 0, 3) == b"")
  let encoded = write_tree([
    Numeric(numeric_array("one", Float64, [1, 1], [Floating(1.0)])),
  ])
  let matrix = encoded[128:].to_owned()
  let oversized = changed(matrix, 4, (matrix[4].to_int() + 8).to_byte())
  for (data, chunk) in [(oversized, 11), (matrix + b"extra", 3)] {
    let out : Array[Byte] = []
    for i = 0; i < 128; i = i + 1 {
      out.push(encoded[i])
    }
    append_element(out, 15, deflate_zlib(data))
    let bytes = Bytes::from_array(out)
    assert_eq(
      error_code(() => {
        ignore(
          read_selected_from(test_source(bytes, 3), [], limits={
            ..default_source_limits(),
            chunk_bytes: chunk,
          }),
        )
      }),
      "invalid-compressed",
    )
  }
}
