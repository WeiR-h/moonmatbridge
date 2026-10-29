///|
fn latin_tree() -> Array[MatNode] raise MatError {
  let n = numeric_array("café", UInt64, [1, 1], [
    Unsigned(18446744073709551615UL),
  ])
  let s : StructArray = {
    name: "résumé",
    shape: [1, 1],
    fields: ["donnée"],
    values: [Numeric({ ..n, name: "", })],
    class_name: Some("Expérience"),
    is_global: true,
  }
  [Numeric(n), Structure(s)]
}

///|
test "explicit Latin1 preserves root field and legacy names across all readers" {
  for compressed in [false, true] {
    let data = write_tree(latin_tree(), compressed~, name_encoding=Latin1)
    let decoded = read_tree(data, name_encoding=Latin1)
    assert_true(
      compare_trees(decoded, read_tree(write_tree(latin_tree()))).content_equal,
    )
    assert_true(
      write_tree(decoded.variables, compressed~, name_encoding=Latin1) == data,
    )
    assert_eq(inspect_roots(data, name_encoding=Latin1)[1].name, "résumé")
    let selected = read_selected(
      data,
      ["résumé", "café"],
      name_encoding=Latin1,
    )
    assert_eq(selected.variables[0].name(), "résumé")
    for chunk in [1, 3, 257] {
      let source = test_source(data, 2)
      let limits = { ..default_source_limits(), chunk_bytes: chunk, }
      assert_true(
        compare_trees(
          decoded,
          read_tree_from(source, limits~, name_encoding=Latin1),
        ).content_equal,
      )
      assert_eq(
        inspect_roots_from(source, limits~, name_encoding=Latin1)[0].name,
        "café",
      )
      assert_eq(
        read_selected_from(source, ["résumé"], limits~, name_encoding=Latin1).variables.length(),
        1,
      )
      assert_eq(
        read_selected_from(source, [], limits~, name_encoding=Latin1).variables.length(),
        0,
      )
    }
    try {
      ignore(read_selected(data, []))
      assert_true(false)
    } catch {
      MatError(code, _, _) => assert_eq(code, "invalid-name")
      _ => assert_true(false)
    }
    try {
      ignore(inspect_roots_from(test_source(data, 1)))
      assert_true(false)
    } catch {
      MatError(code, _, _) => assert_eq(code, "invalid-name")
      _ => assert_true(false)
    }
  }
}

///|
test "Latin1 names use encoded byte quotas and reject nonrepresentable names" {
  let a = numeric_array("éé", Float64, [1, 1], [Floating(-0.0)])
  let limits = { ..default_limits(), max_name_bytes: 2, }
  let data = write_mat([a], limits~, name_encoding=Latin1)
  assert_eq(
    read_mat(data, limits~, name_encoding=Latin1).arrays[0].name,
    "éé",
  )
  let z = { ..a, name: "月", }
  try {
    ignore(write_mat([z], name_encoding=Latin1))
    assert_true(false)
  } catch {
    MatError(code, _, _) => assert_eq(code, "invalid-name")
    _ => assert_true(false)
  }
  let bad = { ..a, name: "a\u{0000}", }
  try {
    ignore(write_mat([bad], name_encoding=Latin1))
    assert_true(false)
  } catch {
    MatError(code, _, _) => assert_eq(code, "invalid-name")
    _ => assert_true(false)
  }
}
