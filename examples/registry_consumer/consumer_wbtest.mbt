///|
test "published compressed dense data preserves complex and uint64" {
  assert_eq(@mat.version(), "0.0.5")
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
