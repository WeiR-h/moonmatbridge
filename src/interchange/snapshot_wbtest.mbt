///|
test "snapshot archives exact float32 float64 integer complex and sparse capacity planes" {
  let f64 = @mat.raw_array("f64", @mat.Float64, [1, 2], b"\x42\x00\x00\x00\x00\x00\xf8\x7f\x00\x00\x00\x00\x00\x00\x00\x80", imag=b"\x7f\x00\x00\x00\x00\x00\xf8\xff\x00\x00\x00\x00\x00\x00\x00\x00", is_global=true)
  let f32 = @mat.raw_array("f32", @mat.Float32, [2, 1], b"\x01\x00\xc0\x7f\x00\x00\x00\x80")
  let sparse = @mat.raw_sparse_array("s", @mat.Float64, [10, 2], [2, 9, -1], [0, 1, 2], f64.real + b"\x00\x00\x00\x00\x00\x00\xf0\x3f", nzmax=5)
  let items = [@mat.Dense(f64), @mat.Dense(f32), @mat.Sparse(sparse), @mat.Dense(sample()[2])]
  let text = to_snapshot(items)
  let restored = from_snapshot(text)
  assert_true(@mat.write_document(restored) == @mat.write_document(items))
  assert_true(@mat.write_document(@mat.read_document(@mat.write_document(restored, compressed=true)).variables) == @mat.write_document(items))
  assert_true(text.contains("420000000000f87f"))
}

///|
test "snapshot refuses unknown fields invalid hex duplicate names and metadata mismatches" {
  let check = fn(text : String) { ignore(from_snapshot(text)) catch { error => return error.code() }; "no-error" }
  let text = to_snapshot([@mat.Dense(@mat.raw_array("x", @mat.Float32, [1, 1], b"\x00\x00\x00\x80"))])
  assert_eq(check(text.replace(old="00000080", new="g0000080")), "invalid-json")
  assert_eq(check(text.replace(old="00000080", new="0000080")), "invalid-json")
  assert_eq(check(text.replace(old="column-major", new="row-major")), "invalid-json")
  assert_eq(check(text.replace(old="\"real_hex\"", new="\"payload_hex\"")), "invalid-json")
  let doubled = to_snapshot([@mat.Dense(@mat.raw_array("x", @mat.Float32, [1, 1], b"\x00\x00\x00\x80")), @mat.Dense(@mat.raw_array("y", @mat.Float32, [1, 1], b"\x00\x00\x00\x80"))])
  assert_eq(check(doubled.replace(old="\"y\"", new="\"x\"")), "duplicate-name")
  assert_eq(check("{\"schema\":\"moonmatbridge/snapshot/1\",\"order\":\"column-major\",\"byte_order\":\"little\",\"variables\":[],\"typo\":true}"), "invalid-json")
}
