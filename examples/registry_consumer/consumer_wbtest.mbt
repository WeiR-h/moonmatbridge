///|
test "published compressed dense data preserves complex and uint64" {
  assert_eq(@mat.version(), "0.0.19")
  let id = @mat.numeric_array("id", @mat.UInt64, [1, 2], [
    Unsigned(9007199254740993UL),
    Unsigned(18446744073709551615UL),
  ])
  let wave = @mat.numeric_array(
    "wave", @mat.Float64, [1, 2], [Floating(1.0), Floating(-2.0)],
    imaginary=[Floating(0.5), Floating(3.0)],
  )
  let bytes = @mat.write_mat([id, wave], compressed=true)
  let restored = @mat.read_mat(bytes)
  match restored.get("id").unwrap().value(1) {
    Unsigned(value) => assert_eq(value, 18446744073709551615UL)
    _ => fail("Expected uint64 payload")
  }
  assert_true(restored.get("wave").unwrap().imag == wave.imag)
  assert_true(bytes == @mat.write_mat([id, wave], compressed=true))
}

///|
test "published recursive tree preserves cell struct and UTF8 text" {
  let label = @mat.Character(@mat.utf8_char_array("", [1, 3], "科研🌙"))
  let record : @mat.StructArray = {
    name: "record", shape: [1, 1], fields: ["samples"],
    values: [@mat.Cell({ name: "", shape: [1, 1], values: [label], is_global: false })],
    class_name: None, is_global: true,
  }
  let bytes = @mat.write_tree([@mat.Structure(record)], compressed=true)
  let file = @mat.read_tree(bytes)
  assert_true(bytes == @mat.write_tree(file.variables, compressed=true))
  let info = @wire.tree_info(file).stringify()
  assert_true(info.contains("struct") && info.contains("cell") && info.contains("miUTF8"))
}

///|
test "published strict selection and root metadata preserve order and validate omitted data" {
  let values = [@mat.Numeric(@mat.numeric_array("a", @mat.Float64, [1, 1], [Floating(1.0)])),
    @mat.Cell({name: "c", shape: [1, 1], values: [@mat.Character(@mat.utf8_char_array("", [1, 1], "月"))], is_global: true})]
  for compressed in [false, true] {
    let bytes = @mat.write_tree(values, compressed~)
    let roots = @mat.inspect_roots(bytes)
    assert_eq(roots[0].class_id, 6)
    assert_true(roots[1].is_global && roots[1].compressed == compressed)
    let selected = @mat.read_selected(bytes, ["c", "a"])
    assert_eq(selected.variables[0].name(), "c")
    assert_eq(selected.variables[1].name(), "a")
    assert_eq(@mat.read_selected(bytes, []).variables.length(), 0)
    if compressed {
      let raw = bytes.to_array()
      raw[raw.length() - 1] = (raw[raw.length() - 1].to_int() ^ 1).to_byte()
      let code = try { ignore(@mat.read_selected(Bytes::from_array(raw), ["a"])); "accepted" } catch { e => e.code() }
      assert_eq(code, "invalid-zlib")
    }
  }
}

///|
test "published array operations retain NaN payload and negative zero" {
  let a = @mat.raw_array("a", @mat.Float64, [1, 2],
    b"\x01\x00\x00\x00\x00\x00\xf8\x7f\x00\x00\x00\x00\x00\x00\x00\x80")
  let sampled = a.gather_axis(1, [1, 0, 1])
  assert_true(sampled.real == b"\x00\x00\x00\x00\x00\x00\x00\x80\x01\x00\x00\x00\x00\x00\xf8\x7f\x00\x00\x00\x00\x00\x00\x00\x80")
  let window = sampled.slice([0, 1], [1, 1])
  let joined = @mat.concat_arrays("joined", [window, window], 1)
  assert_true(joined.real == b"\x01\x00\x00\x00\x00\x00\xf8\x7f\x01\x00\x00\x00\x00\x00\xf8\x7f")
}

///|
test "published mixed CSC snapshots do not expand the full shape" {
  let pointers = Array::make(1001, 1)
  pointers[0] = 0
  let sparse = @mat.raw_sparse_array(
    "s", @mat.Float64, [1000000, 1000], [999999], pointers,
    b"\x00\x00\x00\x00\x00\x00\xf0\x3f",
  )
  let id = @mat.numeric_array("id", @mat.UInt64, [1, 1], [Unsigned(18446744073709551615UL)])
  let before = @mat.read_document(@mat.write_document([
    @mat.Sparse(sparse), @mat.Dense(id),
  ], compressed=true))
  let transformed = @wire.transform_document(before.variables,
    "{\"schema\":\"moonmatbridge/transform/1\",\"operations\":[]}")
  let snapshot = @wire.to_snapshot(transformed)
  let restored = @mat.read_document(@mat.write_document(@wire.from_snapshot(snapshot)))
  assert_true(@mat.compare_documents(before, restored).content_equal)
  assert_eq(sparse.nnz(), 1)
  let failure = try {
    ignore(sparse.to_dense())
    "missing-error"
  } catch {
    error => error.code()
  }
  assert_eq(failure, "element-limit")
}

///|
test "published NPY complex round trip retains both planes" {
  let wave = @mat.numeric_array("wave", @mat.Float64, [1, 2],
    [Floating(1.0), Floating(-2.0)], imaginary=[Floating(0.5), Floating(3.0)])
  let restored = @mat.read_npy(@mat.write_npy(wave), "wave")
  assert_eq(restored.shape, [1, 2])
  assert_true(restored.real == wave.real)
  assert_true(restored.imag == wave.imag)
}

///|
test "published exact diff reports the negative-zero coordinate" {
  let before = @mat.raw_array("signal", @mat.Float64, [1, 1],
    b"\x00\x00\x00\x00\x00\x00\x00\x80")
  let after = @mat.raw_array("signal", @mat.Float64, [1, 1],
    b"\x00\x00\x00\x00\x00\x00\x00\x00")
  let report = @mat.compare_documents(
    @mat.read_document(@mat.write_document([@mat.Dense(before)])),
    @mat.read_document(@mat.write_document([@mat.Dense(after)])),
    max_samples=1,
  )
  assert_true(!report.content_equal)
  assert_eq(report.changed_variables, 1)
  assert_eq(report.variables[0].real_differences, 1)
  assert_eq(report.variables[0].samples[0].coordinates, [0, 0])
}

///|
test "published recursive snapshot and tree comparison preserve exact bits" {
  let value = @mat.raw_array("id", @mat.UInt64, [1,1], b"\xff\xff\xff\xff\xff\xff\xff\xff")
  let nodes = [@mat.Numeric(value)]
  let restored = @wire.from_tree_snapshot(@wire.to_tree_snapshot(nodes))
  let before = @mat.read_tree(@mat.write_tree(nodes))
  let after = @mat.read_tree(@mat.write_tree(restored))
  assert_true(@mat.compare_trees(before,after).content_equal)
}
///|
test "published CSC order duplicates and dense values" {
  let a = @mat.raw_sparse_array("s", @mat.Logical, [2, 1], [1, 1, 0], [0, 3], b"\x01\x00\x01")
  assert_false(a.is_canonical())
  assert_true(a.to_dense().real == b"\x01\x01")
  let tree = @mat.read_tree(@mat.write_tree([@mat.Csc(a)]))
  let restored = @mat.read_tree(@mat.write_tree(@wire.from_tree_snapshot(@wire.to_tree_snapshot(tree.variables))))
  assert_true(@mat.compare_trees(tree, restored).content_equal)
}
///|
test "published data sources support short reads and selected ownership" {
  let bytes=@mat.write_tree([@mat.Numeric(@mat.raw_array("id",@mat.UInt64,[1,1],b"\xff\xff\xff\xff\xff\xff\xff\xff"))])
  let source : @mat.MatSource={size:bytes.length(),read_into:(offset,target,start,length)=>{
    let n=if length>3 {3} else {length}
    for i=0;i<n;i=i+1{target[start+i]=bytes[offset+i]}
    n
  },}
  assert_eq(@mat.inspect_roots_from(source)[0].class_id,15)
  let selected=@mat.read_selected_from(source,["id"])
  assert_true(@mat.write_tree(selected.variables)==bytes)
}

///|
test "published tolerance comparison preserves exact and close results" {
  let a=@mat.raw_array("x",@mat.Float64,[1,1],b"\x00\x00\x00\x00\x00\x00\x00\x80")
  let b={..a,real:b"\x00\x00\x00\x00\x00\x00\x00\x00",}
  let left=@mat.read_tree(@mat.write_tree([@mat.Numeric(a)]))
  let right=@mat.read_tree(@mat.write_tree([@mat.Numeric(b)]))
  let report=@mat.compare_trees_close(left,right)
  assert_true(report.within_tolerance && !report.exact_equal)
  assert_true(@wire.tree_close_json(report).stringify().contains("moonmatbridge/tree-close/1"))
}
