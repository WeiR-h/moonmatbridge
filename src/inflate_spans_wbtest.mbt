///|
test "literal spans preserve short tails allocation edges and exact expansion limits" {
  for size in [1, 7, 8, 9, 255, 256, 257, 4097] {
    let bytes = Bytes::makei(size, i => ((i * 73 + i / 251) & 255).to_byte())
    let encoded = deflate_zlib(bytes)
    assert_true(inflate_zlib(encoded, max_bytes=size) == bytes)
    assert_eq(
      error_code(() => ignore(inflate_zlib(encoded, max_bytes=size - 1))),
      "expanded-limit",
    )
  }
  for size = 0; size < 40; size = size + 1 {
    let node = Numeric(
      raw_array(
        "short",
        UInt8,
        [1, size],
        Bytes::makei(size, i => ((i * 97 + 17) & 255).to_byte()),
      ),
    )
    let bytes = write_tree([node], compressed=true)
    for chunk in [1, 3, 5, 11] {
      assert_true(
        compare_trees(
          read_tree(bytes),
          read_tree_from(test_source(bytes, 1), limits={
            ..default_source_limits(),
            chunk_bytes: chunk,
          }),
        ).content_equal,
      )
    }
  }
}
