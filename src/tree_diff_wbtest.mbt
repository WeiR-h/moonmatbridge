///|
fn diff_fixture(real : Bytes) -> MatTree raise MatError {
  let numeric = raw_array("value", Float64, [1, 1], real)
  let value = Numeric({ ..numeric, name: "", })
  let cell : CellArray = {
    name: "",
    shape: [1, 1],
    values: [value],
    is_global: false,
  }
  let root : StructArray = {
    name: "a.b",
    shape: [1, 1],
    fields: ["[x].y"],
    values: [Cell(cell)],
    class_name: Some("Experiment"),
    is_global: true,
  }
  { description: "", little_endian: true, variables: [Structure(root)], }
}

///|
test "tree diff locates exact bits through object struct field and cell paths" {
  let left = diff_fixture(b"\x00\x00\x00\x00\x00\x00\x00\x80")
  let right = diff_fixture(b"\x00\x00\x00\x00\x00\x00\x00\x00")
  let report = compare_trees(left, right)
  assert_eq(report.differences, 1)
  assert_true(!report.content_equal && !report.truncated)
  assert_eq(report.samples[0].path, [
    Root("a.b"),
    StructElement(0),
    Field("[x].y"),
    CellElement(0),
  ])
  assert_eq(report.samples[0].kind, "real")
  assert_eq(report.samples[0].coordinates, [0, 0])
  assert_true(report.samples[0].before != report.samples[0].after)
  assert_true(compare_trees(left, left).content_equal)
}

///|
test "tree diff matches fields by name while reporting field and root order" {
  let n1 = raw_array("one", UInt8, [1, 1], b"\x01")
  let n2 = raw_array("two", UInt8, [1, 1], b"\x02")
  let one = Numeric({ ..n1, name: "", })
  let two = Numeric({ ..n2, name: "", })
  let a : StructArray = {
    name: "root",
    shape: [1, 1],
    fields: ["a", "b"],
    values: [one, two],
    class_name: None,
    is_global: false,
  }
  let b = { ..a, fields: ["b", "a"], values: [two, one], }
  let left : MatTree = {
    description: "left",
    little_endian: false,
    variables: [Structure(a)],
  }
  let right : MatTree = {
    description: "right",
    little_endian: true,
    variables: [Structure(b)],
  }
  let report = compare_trees(left, right)
  assert_eq(report.differences, 1)
  assert_eq(report.samples[0].kind, "field_order")
  let roots = mixed_tree()
  let x = { ..left, variables: roots, }
  let y = { ..left, variables: [roots[1], roots[0]], }
  let order = compare_trees(x, y)
  assert_true(order.variable_order_changed && order.content_equal)
  assert_eq(order.differences, 0)
}

///|
test "tree diff global sample budget counts all changes after truncation" {
  let a = Numeric(raw_array("x", UInt8, [1, 3], b"\x00\x00\x00"))
  let b = Numeric(raw_array("x", UInt8, [1, 3], b"\x01\x02\x03"))
  let left : MatTree = { description: "", little_endian: true, variables: [a], }
  let right = { ..left, variables: [b], }
  for limit in [0, 1, 2] {
    let report = compare_trees(left, right, max_samples=limit)
    assert_eq(report.differences, 3)
    assert_eq(report.samples.length(), limit)
    assert_true(report.truncated)
  }
  assert_eq(
    error_code(() => ignore(compare_trees(left, right, max_samples=257))),
    "invalid-limits",
  )
  assert_eq(
    error_code(() => {
      ignore(
        compare_trees({ ..left, variables: [a, a], }, right, max_samples=0),
      )
    }),
    "duplicate-name",
  )
}

///|
test "tree diff checks chars sparse capacity complex bits and recursive budgets" {
  let sparse = raw_sparse_array(
    "s",
    Float64,
    [10, 1],
    [2, -1],
    [0, 1],
    b"\x00\x00\x00\x00\x00\x00\x00\x80\x42\x00\x00\x00\x00\x00\xf8\x7f",
    nzmax=4,
  )
  let char = utf8_char_array("c", [1, 1], "甲")
  let left : MatTree = {
    description: "",
    little_endian: true,
    variables: [Csc(sparse), Character(char)],
  }
  let right = {
    ..left,
    variables: [
      Csc({ ..sparse, nzmax: 5, }),
      Character(utf8_char_array("c", [1, 1], "乙")),
    ],
  }
  let report = compare_trees(left, right)
  assert_true(!report.content_equal)
  assert_true(report.samples.any(s => s.kind == "nzmax"))
  assert_true(report.samples.any(s => s.kind == "char_units"))
  let nested = diff_fixture(b"\x42\x00\x00\x00\x00\x00\xf8\x7f")
  assert_eq(
    error_code(() => {
      ignore(
        compare_trees(nested, nested, max_samples=0, tree_limits={
          max_depth: 2,
          max_nodes: 50,
          max_fields: 10,
        }),
      )
    }),
    "depth-limit",
  )
}
