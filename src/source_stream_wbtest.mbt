///|
test "streamed sources cross every small chunk boundary and check omitted children" {
  let bytes = write_tree(mixed_tree())
  for chunk in [1, 3, 7, 11, 31, 127, 257] {
    let limits = {
      ..default_source_limits(),
      chunk_bytes: chunk,
      max_buffered_root_bytes: 128,
    }
    let source = test_source(bytes, 3)
    assert_true(
      compare_trees(read_tree(bytes), read_tree_from(source, limits~)).content_equal,
    )
    assert_eq(inspect_roots_from(source, limits~).length(), 2)
    assert_eq(read_selected_from(source, [], limits~).variables.length(), 0)
  }
  // The valid requested root precedes an invalid nested UTF8 scalar.
  let first = Numeric(numeric_array("first", Float64, [1, 1], [Floating(1.0)]))
  let cell : CellArray = {
    name: "bad",
    shape: [1, 1],
    values: [Character(utf8_char_array("", [1, 1], "x"))],
    is_global: false,
  }
  let bytes = write_tree([first, Cell(cell)])
  let bad = changed(bytes, bytes.length() - 8, b'\xff')
  for names in [[], ["first"]] {
    assert_true(
      error_code(() => {
        ignore(
          read_selected_from(test_source(bad, 2), names, limits={
            ..default_source_limits(),
            chunk_bytes: 3,
          }),
        )
      }) !=
      "no-error",
    )
  }
}

///|
test "streamed CSC retains inactive capacity duplicate rows and original planes" {
  let sparse : SparseArray = {
    name: "slots",
    shape: [3, 1],
    dtype: Float64,
    row_indices: [2, 0, 2, -123],
    col_ptrs: [0, 3],
    real: b"\x00\x00\x00\x00\x00\x00\x00\x80\x01\x00\x00\x00\x00\x00\xf8\x7f\x00\x00\x00\x00\x00\x00\xf0\x3f\x00\x00\x00\x00\x00\x00\x00\x00",
    imag: None,
    nzmax: 7,
    is_global: true,
  }
  let bytes = write_tree([Csc(sparse)])
  for names in [[], ["slots"]] {
    let source = test_source(bytes, 1)
    let result = read_selected_from(source, names, limits={
      ..default_source_limits(),
      chunk_bytes: 3,
    })
    if !names.is_empty() {
      assert_true(compare_trees(read_tree(bytes), result).content_equal)
    }
  }
  let outer = tag(bytes, 128, bytes.length(), true)
  let flags = tag(bytes, outer.start, outer.start + outer.size, true)
  let dims = tag(bytes, flags.next, outer.start + outer.size, true)
  let name = tag(bytes, dims.next, outer.start + outer.size, true)
  let ir = tag(bytes, name.next, outer.start + outer.size, true)
  let bad = changed(bytes, ir.start, b'\x03')
  assert_eq(
    error_code(() => ignore(read_selected_from(test_source(bad, 1), []))),
    "invalid-sparse",
  )
  let jc = tag(bytes, ir.next, outer.start + outer.size, true)
  let bad_pointer = changed(bytes, jc.start, b'\x01')
  assert_eq(
    error_code(() => ignore(read_selected_from(test_source(bad_pointer, 1), []))),
    "invalid-sparse",
  )
}

///|
test "source structural limits apply to omitted nodes in both encodings" {
  for compressed in [false, true] {
    let bytes = write_tree(mixed_tree(), compressed~)
    let source = test_source(bytes, 3)
    assert_eq(
      error_code(() => {
        ignore(
          read_selected_from(source, [], tree_limits={
            ..default_tree_limits(),
            max_depth: 2,
          }),
        )
      }),
      "depth-limit",
    )
    assert_eq(
      error_code(() => {
        ignore(
          read_selected_from(source, [], tree_limits={
            ..default_tree_limits(),
            max_nodes: 2,
          }),
        )
      }),
      "node-limit",
    )
    assert_eq(
      error_code(() => {
        ignore(
          read_selected_from(source, [], tree_limits={
            ..default_tree_limits(),
            max_fields: 1,
          }),
        )
      }),
      "invalid-fields",
    )
    assert_eq(
      error_code(() => {
        ignore(
          read_selected_from(source, [], limits={
            ..default_source_limits(),
            max_elements: 1,
          }),
        )
      }),
      "element-limit",
    )
    assert_eq(
      error_code(() => {
        ignore(
          read_selected_from(source, [], limits={
            ..default_source_limits(),
            max_variables: 1,
          }),
        )
      }),
      "variable-limit",
    )
  }
}

///|
test "source metadata quota is cumulative and duplicate roots are rejected" {
  let values = []
  for i = 0; i < 8; i = i + 1 {
    values.push(
      Numeric(
        numeric_array("variable_" + i.to_string(), Float64, [1, 1], [
          Floating(1.0),
        ]),
      ),
    )
  }
  for compressed in [false, true] {
    let bytes = write_tree(values, compressed~)
    assert_eq(
      error_code(() => {
        ignore(
          read_selected_from(test_source(bytes, 3), [], limits={
            ..default_source_limits(),
            max_metadata_bytes: 128,
          }),
        )
      }),
      "metadata-limit",
    )
    let one = write_tree([values[0]], compressed~)
    let duplicate = one + one[128:].to_owned()
    assert_eq(
      error_code(() => ignore(inspect_roots_from(test_source(duplicate, 3)))),
      "duplicate-name",
    )
  }
}

///|
test "source expansion quota is cumulative even after a selected root" {
  let raw = Bytes::make(512, b'\x01')
  let one = Numeric(raw_array("one", UInt8, [1, 512], raw))
  let two = Numeric(raw_array("two", UInt8, [1, 512], raw))
  let bytes = write_tree([one, two], compressed=true)
  let first = tag(bytes, 128, bytes.length(), true)
  let maximum = inflate_window(bytes, first.start, first.size, 4096, Some(true)).length()
  assert_eq(
    error_code(() => {
      ignore(
        read_selected_from(test_source(bytes, 3), ["one"], limits={
          ..default_source_limits(),
          max_expanded_bytes: maximum,
        }),
      )
    }),
    "expanded-limit",
  )
}
