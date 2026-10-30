///|
test "Latin1 mixed metadata budget is exact and charged before either sink encoding" {
  let mut name = ""
  for i = 0; i < 110; i = i + 1 {
    name = name + "é"
  }
  let nodes : Array[MatNode] = [
    Structure({
      name,
      shape: [1, 1],
      fields: ["naïve"],
      values: [Character(utf8_char_array("", [1, 2], "xy"))],
      class_name: Some("Café"),
      is_global: true,
    }),
  ]
  for compressed in [false, true] {
    let data = write_tree(nodes, compressed~, name_encoding=Latin1)
    let good : SourceLimits = {
      ..default_source_limits(),
      max_metadata_bytes: 136,
      chunk_bytes: 7,
    }
    assert_true(
      compare_trees(
        read_tree(data, name_encoding=Latin1),
        read_tree_from(test_source(data, 3), limits=good, name_encoding=Latin1),
      ).content_equal,
    )
    assert_eq(
      inspect_roots_from(
        test_source(data, 3),
        limits=good,
        name_encoding=Latin1,
      ).length(),
      1,
    )
    assert_eq(
      error_code(() => {
        ignore(
          read_selected_from(
            test_source(data, 3),
            [],
            limits={ ..good, max_metadata_bytes: 135, },
            name_encoding=Latin1,
          ),
        )
      }),
      "metadata-limit",
    )
    let calls = [0]
    let sink : MatSink = {
      write_from: (_, _, _, n) => {
        calls[0] = calls[0] + 1
        n
      },
    }
    assert_eq(
      error_code(() => {
        ignore(
          write_tree_to(
            nodes,
            sink,
            compressed~,
            limits={ ..default_write_limits(), max_metadata_bytes: 135, },
            name_encoding=Latin1,
          ),
        )
      }),
      "metadata-limit",
    )
    assert_eq(calls[0], 0)
    assert_true(
      write_tree_to(
        nodes,
        sink,
        compressed~,
        limits={
          ..default_write_limits(),
          max_metadata_bytes: 136,
          chunk_bytes: 7,
        },
        name_encoding=Latin1,
      ) >
      128,
    )
  }
}

///|
test "cumulative expansion boundary agrees for tree selected and directory APIs" {
  let nodes = mixed_tree()
  let expanded = write_tree(nodes).length() - 128
  let bytes = write_tree(nodes, compressed=true)
  for extra in [0, -1] {
    let memory = { ..default_limits(), max_expanded_bytes: expanded + extra, }
    let streamed = {
      ..default_source_limits(),
      max_expanded_bytes: expanded + extra,
      chunk_bytes: 7,
    }
    let expected = if extra == 0 { "no-error" } else { "expanded-limit" }
    assert_eq(
      error_code(() => ignore(read_tree(bytes, limits=memory))),
      expected,
    )
    assert_eq(
      error_code(() => ignore(read_selected(bytes, [], limits=memory))),
      expected,
    )
    assert_eq(
      error_code(() => ignore(inspect_roots(bytes, limits=memory))),
      expected,
    )
    assert_eq(
      error_code(() => {
        ignore(read_tree_from(test_source(bytes, 3), limits=streamed))
      }),
      expected,
    )
    assert_eq(
      error_code(() => {
        ignore(read_selected_from(test_source(bytes, 3), [], limits=streamed))
      }),
      expected,
    )
    assert_eq(
      error_code(() => {
        ignore(inspect_roots_from(test_source(bytes, 3), limits=streamed))
      }),
      expected,
    )
  }
}

///|
test "omitted compressed roots retain checksum errors across all public readers" {
  let bytes = write_tree(mixed_tree(), compressed=true)
  let bad = changed(
    bytes,
    bytes.length() - 1,
    (bytes[bytes.length() - 1].to_int() ^ 1).to_byte(),
  )
  assert_eq(error_code(() => ignore(read_tree(bad))), "invalid-zlib")
  assert_eq(error_code(() => ignore(read_selected(bad, []))), "invalid-zlib")
  assert_eq(error_code(() => ignore(inspect_roots(bad))), "invalid-zlib")
  assert_eq(
    error_code(() => ignore(read_tree_from(test_source(bad, 1)))),
    "invalid-zlib",
  )
  assert_eq(
    error_code(() => ignore(read_selected_from(test_source(bad, 1), []))),
    "invalid-zlib",
  )
  assert_eq(
    error_code(() => ignore(inspect_roots_from(test_source(bad, 1)))),
    "invalid-zlib",
  )
}

///|
test "invalid inline matrix flags fail consistently at odd block boundaries" {
  let bytes = write_tree(mixed_tree())
  let bad = changed(changed(bytes, 138, b'\x05'), 139, b'\x00')
  let expected = error_code(() => ignore(read_tree(bad)))
  assert_true(expected != "no-error")
  assert_eq(error_code(() => ignore(read_selected(bad, []))), expected)
  assert_eq(error_code(() => ignore(inspect_roots(bad))), expected)
  for chunk in [1, 3, 7] {
    let limits = { ..default_source_limits(), chunk_bytes: chunk, }
    assert_eq(
      error_code(() => ignore(read_tree_from(test_source(bad, 2), limits~))),
      expected,
    )
    assert_eq(
      error_code(() => {
        ignore(read_selected_from(test_source(bad, 2), [], limits~))
      }),
      expected,
    )
    assert_eq(
      error_code(() => ignore(inspect_roots_from(test_source(bad, 2), limits~))),
      expected,
    )
  }
}
