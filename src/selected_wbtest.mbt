///|
test "selected mixed roots preserve requested order and inspect flags without offsets" {
  for compressed in [false, true] {
    let bytes = write_tree(mixed_tree(), compressed~)
    let roots = inspect_roots(bytes)
    assert_eq(roots.length(), 2)
    assert_eq(roots[0].name, "experiment")
    assert_eq(roots[0].class_id, 2)
    assert_true(roots[0].is_global && roots[0].compressed == compressed)
    assert_eq(roots[1].class_id, 4)
    let selected = read_selected(bytes, ["title", "experiment"])
    assert_eq(selected.variables[0].name(), "title")
    assert_eq(selected.variables[1].name(), "experiment")
    assert_true(
      write_tree(selected.variables) ==
      write_tree(read_tree(bytes).select(["title", "experiment"])),
    )
    assert_eq(read_selected(bytes, []).variables.length(), 0)
    assert_eq(
      error_code(() => ignore(read_selected(bytes, ["missing"]))),
      "missing-variable",
    )
    assert_eq(
      error_code(() => ignore(read_selected(bytes, ["title", "title"]))),
      "duplicate-name",
    )
  }
}

///|
test "unselected numeric conversions and aggregate budgets are still validated" {
  let good = Numeric(
    numeric_array("good", Float64, [1, 2], [Floating(1.0), Floating(2.0)]),
  )
  let bad = Numeric(
    numeric_array("bad", UInt64, [1, 1], [Unsigned(18446744073709551615UL)]),
  )
  let bytes = write_tree([good, bad])
  let first = tag(bytes, 128, bytes.length(), true)
  let second = tag(bytes, first.next, bytes.length(), true)
  let flags = tag(bytes, second.start, second.start + second.size, true)
  let dims = tag(bytes, flags.next, second.start + second.size, true)
  let name = tag(bytes, dims.next, second.start + second.size, true)
  // Stored signed -1 cannot safely convert to the declared uint64 class.
  let changed = changed(bytes, name.next, b'\x0c')
  assert_eq(error_code(() => ignore(read_tree(changed))), "value-range")
  assert_eq(
    error_code(() => ignore(read_selected(changed, ["good"]))),
    "value-range",
  )
  assert_eq(error_code(() => ignore(inspect_roots(changed))), "value-range")
  let many = write_tree([
    good,
    Numeric(
      numeric_array("other", Float64, [1, 2], [Floating(3.0), Floating(4.0)]),
    ),
  ])
  assert_eq(
    error_code(() => {
      ignore(
        read_selected(many, ["good"], limits={
          ..default_limits(),
          max_elements: 3,
        }),
      )
    }),
    "element-limit",
  )
}

///|
test "unselected sparse indexes and UTF8 content cannot bypass checks" {
  let good = Numeric(numeric_array("good", Float64, [1, 1], [Floating(1.0)]))
  let sparse = Csc(
    raw_sparse_array(
      "s",
      Float64,
      [3, 2],
      [0, 2],
      [0, 1, 2],
      Bytes::make(16, b'\x00'),
    ),
  )
  let bytes = write_tree([good, sparse])
  let first = tag(bytes, 128, bytes.length(), true)
  let second = tag(bytes, first.next, bytes.length(), true)
  let flags = tag(bytes, second.start, second.start + second.size, true)
  let dims = tag(bytes, flags.next, second.start + second.size, true)
  let name = tag(bytes, dims.next, second.start + second.size, true)
  let rows = tag(bytes, name.next, second.start + second.size, true)
  let bad = changed(bytes, rows.start, b'\x03')
  assert_eq(error_code(() => ignore(read_tree(bad))), "invalid-sparse")
  assert_eq(
    error_code(() => ignore(read_selected(bad, ["good"]))),
    "invalid-sparse",
  )
  assert_eq(error_code(() => ignore(inspect_roots(bad))), "invalid-sparse")
  let text = write_tree([
    good,
    Character(utf8_char_array("label", [1, 1], "月")),
  ])
  let bad_text = changed(text, text.length() - 8, b'\xff')
  assert_eq(error_code(() => ignore(read_tree(bad_text))), "invalid-char")
  assert_eq(
    error_code(() => ignore(read_selected(bad_text, ["good"]))),
    "invalid-char",
  )
}

///|
test "empty selection still checks compressed checksums truncation and recursive limits" {
  let compressed = write_tree(mixed_tree(), compressed=true)
  let corrupt = changed(
    compressed,
    compressed.length() - 1,
    (compressed[compressed.length() - 1].to_int() ^ 1).to_byte(),
  )
  assert_eq(
    error_code(() => ignore(read_selected(corrupt, []))),
    "invalid-zlib",
  )
  assert_eq(error_code(() => ignore(inspect_roots(corrupt))), "invalid-zlib")
  assert_eq(
    error_code(() => {
      ignore(
        read_selected(compressed, [], tree_limits={
          ..default_tree_limits(),
          max_depth: 1,
        }),
      )
    }),
    "depth-limit",
  )
  let plain = write_tree([mixed_tree()[0]])
  for size = 0; size < plain.length(); size = size + 1 {
    if size != 128 {
      assert_true(
        error_code(() => ignore(read_selected(plain[0:size].to_owned(), []))) !=
        "no-error",
      )
    }
  }
}
