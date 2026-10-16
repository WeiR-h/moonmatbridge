///|
fn mixed_tree() -> Array[MatNode] raise MatError {
  let number = numeric_array("temporary", UInt64, [1, 1], [
    Unsigned(18446744073709551615UL),
  ])
  let child = Numeric({ ..number, name: "", })
  let text = Character(utf8_char_array("", [1, 3], "科研🌙"))
  let cells : CellArray = {
    name: "",
    shape: [1, 2],
    values: [child, text],
    is_global: false,
  }
  let record : StructArray = {
    name: "experiment",
    shape: [1, 1],
    fields: ["samples", "label"],
    values: [Cell(cells), text],
    class_name: None,
    is_global: true,
  }
  [Structure(record), Character(utf8_char_array("title", [1, 2], "实验"))]
}

///|
test "recursive cell struct char preserves Chinese nonBMP exact uint64 and global" {
  let values = mixed_tree()
  for compressed in [false, true] {
    let bytes = write_tree(values, compressed~)
    let file = read_tree(bytes)
    assert_eq(file.variables.length(), 2)
    assert_true(write_tree(file.variables, compressed~) == bytes)
    match file.variables[0] {
      Structure(a) => {
        assert_true(a.is_global)
        assert_eq(a.fields, ["samples", "label"])
        match a.values[0] {
          Cell(c) =>
            match c.values[0] {
              Numeric(n) => {
                assert_eq(n.name, "")
                assert_eq(n.index([0, 0]), 0)
                assert_true(n.real == b"\xff\xff\xff\xff\xff\xff\xff\xff")
              }
              _ => assert_true(false)
            }
          _ => assert_true(false)
        }
      }
      _ => assert_true(false)
    }
  }
}

///|
test "recursive writer validates shape fields depth nodes and aggregate elements" {
  let values = mixed_tree()
  assert_eq(
    error_code(() => {
      ignore(
        write_tree(values, tree_limits={
          max_depth: 2,
          max_nodes: 100,
          max_fields: 10,
        }),
      )
    }),
    "depth-limit",
  )
  assert_eq(
    error_code(() => {
      ignore(
        write_tree(values, tree_limits={
          max_depth: 64,
          max_nodes: 3,
          max_fields: 10,
        }),
      )
    }),
    "node-limit",
  )
  assert_eq(
    error_code(() => {
      ignore(
        write_tree(values, tree_limits={
          max_depth: 64,
          max_nodes: 100,
          max_fields: 1,
        }),
      )
    }),
    "invalid-fields",
  )
  let bad : CellArray = {
    name: "bad",
    shape: [2, 2],
    values: [],
    is_global: false,
  }
  assert_eq(error_code(() => ignore(write_tree([Cell(bad)]))), "payload-size")
  let duplicate : StructArray = {
    name: "bad",
    shape: [0, 0],
    fields: ["a", "a"],
    values: [],
    class_name: None,
    is_global: false,
  }
  assert_eq(
    error_code(() => ignore(write_tree([Structure(duplicate)]))),
    "duplicate-field",
  )
  let limits = { ..default_limits(), max_elements: 5, }
  assert_eq(
    error_code(() => ignore(write_tree(values, limits~))),
    "element-limit",
  )
}

///|
test "recursive reader limits nested matrices before descending" {
  let bytes = write_tree(mixed_tree(), compressed=true)
  assert_eq(
    error_code(() => {
      ignore(
        read_tree(bytes, tree_limits={
          max_depth: 2,
          max_nodes: 100,
          max_fields: 10,
        }),
      )
    }),
    "depth-limit",
  )
  assert_eq(
    error_code(() => {
      ignore(
        read_tree(bytes, tree_limits={
          max_depth: 64,
          max_nodes: 3,
          max_fields: 10,
        }),
      )
    }),
    "node-limit",
  )
  assert_eq(
    error_code(() => {
      ignore(
        read_tree(bytes, tree_limits={
          max_depth: 64,
          max_nodes: 100,
          max_fields: 1,
        }),
      )
    }),
    "invalid-fields",
  )
}

///|
test "all six char storage tags preserve canonical raw units including UTF16 surrogates" {
  let values : Array[MatNode] = []
  for encoding in [Int8Text, UInt8Text, UInt16Text, Utf8, Utf16, Utf32] {
    let data = match encoding {
      UInt16Text | Utf16 => b"\x3d\xd8\x00\xde"
      Utf32 => b"\x00\xf6\x01\x00\x41\x00\x00\x00"
      _ => b"ab"
    }
    values.push(
      Character({
        name: encoding.name(),
        shape: [1, 2],
        encoding,
        data,
        is_global: false,
      }),
    )
  }
  let bytes = write_tree(values)
  assert_true(write_tree(read_tree(bytes).variables) == bytes)
  let invalid : CharArray = {
    name: "x",
    shape: [1, 1],
    encoding: Utf8,
    data: b"\xff",
    is_global: false,
  }
  assert_eq(
    error_code(() => ignore(write_tree([Character(invalid)]))),
    "invalid-char",
  )
  let invalid = { ..invalid, encoding: Utf32, data: b"\x00\xd8\x00\x00", }
  assert_eq(
    error_code(() => ignore(write_tree([Character(invalid)]))),
    "invalid-char",
  )
}

///|
test "legacy object class name and struct array field ordering survive" {
  let a : StructArray = {
    name: "object",
    shape: [1, 2],
    fields: ["value", "note"],
    values: [
      Character(utf8_char_array("", [1, 1], "一")),
      Character(utf8_char_array("", [0, 0], "")),
      Character(utf8_char_array("", [1, 1], "二")),
      Cell({ name: "", shape: [0, 0], values: [], is_global: false, }),
    ],
    class_name: Some("ExperimentRecord"),
    is_global: false,
  }
  let bytes = write_tree([Structure(a)])
  assert_true(write_tree(read_tree(bytes).variables) == bytes)
  assert_eq(read_tree(bytes).select(["object"]).length(), 1)
  assert_eq(
    error_code(() => ignore(read_tree(bytes).select(["missing"]))),
    "missing-variable",
  )
  assert_eq(
    error_code(() => ignore(read_tree(bytes).select(["object", "object"]))),
    "duplicate-name",
  )
}

///|
test "root anonymous names fail while zero-size nested matrix canonicalizes empty double" {
  let number : NumericArray = {
    name: "",
    dtype: Float64,
    shape: [0, 0],
    real: b"",
    imag: None,
    is_global: false,
  }
  assert_eq(
    error_code(() => ignore(write_tree([Numeric(number)]))),
    "invalid-name",
  )
  let bytes = write_mat([]).to_array()
  let a : CellArray = {
    name: "c",
    shape: [1, 1],
    values: [Numeric(number)],
    is_global: false,
  }
  let body = encoded_node(Cell(a)).to_array()
  let dims = tag(Bytes::from_array(body), 16, body.length(), true)
  let name = tag(Bytes::from_array(body), dims.next, body.length(), true)
  let short = body[0:name.next].to_owned()
  append_element(short, 14, b"")
  append_element(bytes, 14, Bytes::from_array(short))
  let restored = read_tree(Bytes::from_array(bytes))
  match restored.variables[0] {
    Cell(c) =>
      match c.values[0] {
        Numeric(n) => assert_eq(n.shape, [0, 0])
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
test "recursive reader refuses truncated children duplicate fields unknown classes and malformed char" {
  let bytes = write_tree([mixed_tree()[0]])
  for size = 129; size < bytes.length(); size = size + 1 {
    assert_true(
      error_code(() => ignore(read_tree(bytes[0:size].to_owned()))) !=
      "no-error",
    )
  }
  let a : StructArray = {
    name: "s",
    shape: [0, 0],
    fields: ["a", "b"],
    values: [],
    class_name: None,
    is_global: false,
  }
  let file = write_tree([Structure(a)])
  let outer = tag(file, 128, file.length(), true)
  let flags = tag(file, outer.start, file.length(), true)
  let dims = tag(file, flags.next, file.length(), true)
  let name = tag(file, dims.next, file.length(), true)
  let width = tag(file, name.next, file.length(), true)
  let table = tag(file, width.next, file.length(), true)
  assert_eq(
    error_code(() => ignore(read_tree(changed(file, table.start + 2, b'a')))),
    "duplicate-field",
  )
  assert_eq(
    error_code(() => ignore(read_tree(changed(file, table.start + 1, b'x')))),
    "invalid-fields",
  )
  assert_eq(
    error_code(() => ignore(read_tree(changed(file, flags.start, b'\x10')))),
    "unsupported-class",
  )
  let chars = write_tree([Character(utf8_char_array("x", [1, 1], "a"))])
  assert_eq(
    error_code(() => {
      ignore(read_tree(changed(chars, chars.length() - 8, b'\xff')))
    }),
    "invalid-char",
  )
}
