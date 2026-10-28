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
}
