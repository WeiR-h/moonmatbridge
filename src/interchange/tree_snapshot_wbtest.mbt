///|
fn snapshot_tree_fixture() -> Array[@mat.MatNode] raise @mat.MatError {
  let id = @mat.raw_array(
    "id",
    @mat.UInt64,
    [1, 1],
    b"\xff\xff\xff\xff\xff\xff\xff\xff",
  )
  let label : @mat.CharArray = {
    name: "",
    shape: [1, 2],
    encoding: @mat.Utf16,
    data: b"\x3d\xd8\x00\xde",
    is_global: false,
  }
  let sparse = @mat.raw_sparse_array(
    "s",
    @mat.Float64,
    [100, 2],
    [2, -1],
    [0, 1, 1],
    b"\x00\x00\x00\x00\x00\x00\x00\x80\x42\x00\x00\x00\x00\x00\xf8\x7f",
    imag=b"\x01\x00\x00\x00\x00\x00\xf8\x7f\x00\x00\x00\x00\x00\x00\x00\x80",
    nzmax=4,
  )
  let cell : @mat.CellArray = {
    name: "",
    shape: [1, 2],
    is_global: false,
    values: [@mat.Numeric({ ..id, name: "", }), @mat.Character(label)],
  }
  let empty : @mat.CharArray = {
    ..label,
    shape: [0, 3, 0],
    encoding: @mat.UInt16Text,
    data: b"",
  }
  let root : @mat.StructArray = {
    name: "experiment",
    shape: [1, 1],
    fields: ["a.b", "signal", "empty"],
    values: [
      @mat.Cell(cell),
      @mat.Csc({ ..sparse, name: "", }),
      @mat.Character(empty),
    ],
    class_name: Some("ExperimentRecord"),
    is_global: true,
  }
  [@mat.Structure(root)]
}

///|
test "tree snapshot preserves recursive object fields UTF16 units uint64 sparse capacity and IEEE bits" {
  let nodes = snapshot_tree_fixture()
  let text = to_tree_snapshot(nodes)
  let restored = from_tree_snapshot(text)
  assert_true(text.contains("moonmatbridge/tree-snapshot/1"))
  assert_true(text.contains("3dd800de"))
  assert_true(text.contains("ffffffffffffffff"))
  assert_true(@mat.write_tree(nodes) == @mat.write_tree(restored))
  let left = @mat.read_tree(@mat.write_tree(nodes, compressed=true))
  let right = @mat.read_tree(@mat.write_tree(restored))
  assert_true(@mat.compare_trees(left, right).content_equal)
  assert_eq(to_tree_snapshot(restored), text)
}

///|
test "tree snapshot rejects malformed payload unknown fields and duplicate root names" {
  let text = to_tree_snapshot(snapshot_tree_fixture())
  let check = fn(value : String) {
    ignore(from_tree_snapshot(value)) catch {
      error => return error.code()
    }
    "ok"
  }
  assert_eq(check(text.replace(old="3dd800de", new="3dd800dg")), "invalid-json")
  assert_eq(check(text.replace(old="little", new="big")), "invalid-json")
  assert_eq(
    check(text.replace(old="data_hex", new="unknown_hex")),
    "invalid-json",
  )
  assert_eq(
    check(text.replace(old="miUTF16", new="unrecognized")),
    "invalid-json",
  )
  assert_eq(check(text.replace(old="ExperimentRecord", new="")), "invalid-name")
  assert_eq(check("{}"), "invalid-json")
  let n = @mat.raw_array("x", @mat.UInt8, [1, 1], b"\x01")
  let doubled = to_tree_snapshot([
    @mat.Numeric(n),
    @mat.Numeric({ ..n, name: "y", }),
  ])
  assert_eq(check(doubled.replace(old="\"y\"", new="\"x\"")), "duplicate-name")
}

///|
test "tree snapshot cumulatively bounds fields nodes elements and decoded bytes" {
  let text = to_tree_snapshot(snapshot_tree_fixture())
  let check = fn(nodes : Int, fields : Int) {
    ignore(
      from_tree_snapshot(text, tree_limits={
        max_depth: 64,
        max_nodes: nodes,
        max_fields: fields,
      }),
    ) catch {
      error => return error.code()
    }
    "ok"
  }
  assert_eq(check(1, 100), "node-limit")
  assert_eq(check(100, 2), "invalid-fields")
  let a = @mat.raw_array(
    "x",
    @mat.Float64,
    [1, 1],
    b"\x00\x00\x00\x00\x00\x00\x00\x00",
  )
  let text = to_tree_snapshot([
    @mat.Numeric(a),
    @mat.Numeric({ ..a, name: "y", }),
  ])
  let code = fn() {
    ignore(
      from_tree_snapshot(text, limits={
        ..@mat.default_limits(),
        max_expanded_bytes: 10,
      }),
    ) catch {
      error => return error.code()
    }
    "ok"
  }
  assert_eq(code(), "expanded-limit")
}

///|
test "tree snapshot preserves empty multi-dimensional arrays and deep supported nesting" {
  let numeric = @mat.raw_array("temp", @mat.UInt8, [0, 2, 0], b"")
  let mut node = @mat.Numeric({ ..numeric, name: "", })
  for _i = 0; _i < 70; _i = _i + 1 {
    node = @mat.Cell({
      name: "",
      shape: [1, 1],
      values: [node],
      is_global: false,
    })
  }
  let root = match node {
    Cell(a) => @mat.Cell({ ..a, name: "deep", })
    _ => node
  }
  let tree : @mat.TreeLimits = {
    max_depth: 80,
    max_nodes: 100,
    max_fields: 10,
  }
  let text = to_tree_snapshot([root], tree_limits=tree)
  let restored = from_tree_snapshot(text, tree_limits=tree)
  assert_true(
    @mat.write_tree([root], tree_limits=tree) ==
    @mat.write_tree(restored, tree_limits=tree),
  )
}

///|
test "tree snapshot accumulates fields across distinct structs and all decoded elements" {
  let empty : @mat.StructArray = {
    name: "left",
    shape: [0, 0],
    fields: ["a", "b"],
    values: [],
    class_name: None,
    is_global: false,
  }
  let nodes = [
    @mat.Structure(empty),
    @mat.Structure({ ..empty, name: "right", }),
  ]
  let text = to_tree_snapshot(nodes)
  let small : @mat.TreeLimits = { ..@mat.default_tree_limits(), max_fields: 3, }
  let encoded_error = fn() {
    ignore(to_tree_snapshot(nodes, tree_limits=small)) catch {
      e => return e.code()
    }
    "ok"
  }
  let decoded_error = fn() {
    ignore(from_tree_snapshot(text, tree_limits=small)) catch {
      e => return e.code()
    }
    "ok"
  }
  assert_eq(encoded_error(), "invalid-fields")
  assert_eq(decoded_error(), "invalid-fields")
  let numeric = @mat.raw_array("x", @mat.UInt8, [1, 2], b"\x01\x02")
  let text = to_tree_snapshot([
    @mat.Numeric(numeric),
    @mat.Numeric({ ..numeric, name: "y", }),
  ])
  let code = fn() {
    ignore(
      from_tree_snapshot(text, limits={
        ..@mat.default_limits(),
        max_elements: 3,
      }),
    ) catch {
      e => return e.code()
    }
    "ok"
  }
  assert_eq(code(), "element-limit")
}
