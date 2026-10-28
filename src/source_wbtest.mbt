///|
fn test_source(bytes : Bytes, maximum : Int) -> MatSource {
  {
    size: bytes.length(),
    read_into: fn(offset, target, start, length) {
      let count = if length > maximum { maximum } else { length }
      for i = 0; i < count; i = i + 1 {
        target[start + i] = bytes[offset + i]
      }
      count
    },
  }
}

///|
test "sources preserve recursive values and request order with partial odd reads" {
  for compressed in [false, true] {
    let bytes = write_tree(mixed_tree(), compressed~)
    let source = test_source(bytes, 7)
    let limits = { ..default_source_limits(), chunk_bytes: 257, }
    let tree = read_tree_from(source, limits~)
    assert_true(compare_trees(tree, read_tree(bytes)).content_equal)
    let selected = read_selected_from(source, ["title", "experiment"], limits~)
    assert_eq(selected.variables[0].name(), "title")
    assert_true(
      write_tree(selected.variables) ==
      write_tree(read_tree(bytes).select(["title", "experiment"])),
    )
    assert_eq(inspect_roots_from(source, limits~)[1].class_id, 4)
    assert_eq(read_selected_from(source, [], limits~).variables.length(), 0)
    assert_eq(
      error_code(() => ignore(read_selected_from(source, ["title", "title"]))),
      "duplicate-name",
    )
    assert_eq(
      error_code(() => ignore(read_selected_from(source, ["absent"]))),
      "missing-variable",
    )
  }
}

///|
test "source quotas cover results root staging and cumulative metadata" {
  let node = Numeric(
    numeric_array("long".repeat(50), Float64, [1, 1], [Floating(1.0)]),
  )
  let source = test_source(write_tree([node]), 16)
  assert_eq(
    error_code(() => {
      ignore(
        read_tree_from(source, limits={
          ..default_source_limits(),
          max_result_bytes: 128,
        }),
      )
    }),
    "result-limit",
  )
  assert_eq(
    error_code(() => {
      ignore(
        read_selected_from(source, [], limits={
          ..default_source_limits(),
          max_metadata_bytes: 128,
        }),
      )
    }),
    "metadata-limit",
  )
  assert_eq(
    error_code(() => {
      ignore(
        read_selected_from(source, [], limits={
          ..default_source_limits(),
          max_buffered_root_bytes: 128,
        }),
      )
    }),
    "source-buffer-limit",
  )
}

///|
test "source errors and invalid omitted variables cannot return partial trees" {
  let bytes = write_tree(mixed_tree(), compressed=true)
  let bad = changed(
    bytes,
    bytes.length() - 1,
    (bytes[bytes.length() - 1].to_int() ^ 1).to_byte(),
  )
  assert_eq(
    error_code(() => ignore(read_selected_from(test_source(bad, 7), []))),
    "invalid-zlib",
  )
  for count in [-1, 0, 200] {
    let source : MatSource = {
      size: 128,
      read_into: (_offset, _target, _start, _length) => count,
    }
    assert_eq(error_code(() => ignore(inspect_roots_from(source))), "io-error")
  }
  assert_eq(
    error_code(() => {
      ignore(
        read_tree_from(test_source(bytes, 7), limits={
          ..default_source_limits(),
          chunk_bytes: 0,
        }),
      )
    }),
    "invalid-limits",
  )
}

///|
test "source results own data and normalized result quota is exact" {
  let encoded = write_tree(mixed_tree())
  let backing = FixedArray::makei(encoded.length(), i => encoded[i])
  let source : MatSource = {
    size: backing.length(),
    read_into: (offset, target, start, length) => {
      for i = 0; i < length; i = i + 1 {
        target[start + i] = backing[offset + i]
      }
      length
    },
  }
  let result = read_tree_from(source, limits={
    ..default_source_limits(),
    max_result_bytes: encoded.length(),
  })
  assert_true(write_tree(result.variables) == encoded)
  assert_eq(
    error_code(() => {
      ignore(
        read_tree_from(source, limits={
          ..default_source_limits(),
          max_result_bytes: encoded.length() - 1,
        }),
      )
    }),
    "result-limit",
  )
  for i = 0; i < backing.length(); i = i + 1 {
    backing[i] = b'\x00'
  }
  assert_true(write_tree(result.variables) == encoded)
}
