///|
test "name option parsing accepts explicit codecs and rejects malformed budgets" {
  assert_true(name_encoding_options("{}") == @mat.Utf8)
  assert_true(
    name_encoding_options("{\"name_encoding\":\"latin1\"}") == @mat.Latin1,
  )
  for
    text in [
      "[]",
      "{",
      "{\"name_encoding\":42}",
      "{\"name_encoding\":\"guess\"}",
      "{\"unknown\":true}",
      " ".repeat(8193),
    ] {
    let code = try {
      ignore(name_encoding_options(text))
      "accepted"
    } catch {
      e => e.code()
    }
    assert_eq(code, "invalid-json")
  }
}

///|
test "tree snapshot fails encoded budget before returning a document" {
  let a = @mat.raw_array("value", @mat.UInt8, [1, 1], b"\x01")
  let size = @mat.write_tree([@mat.Numeric(a)]).length()
  let limits : @mat.Limits = {
    ..@mat.default_limits(),
    max_file_bytes: size,
    max_expanded_bytes: size,
  }
  let code = try {
    ignore(to_tree_snapshot([@mat.Numeric(a)], limits~))
    "accepted"
  } catch {
    e => e.code()
  }
  assert_eq(code, "invalid-json")
}
