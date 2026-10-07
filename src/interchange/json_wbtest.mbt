///|
fn json_error(text : String) -> String {
  try {
    ignore(from_json(text))
    "no-error"
  } catch {
    error => error.code()
  }
}

///|
test "sample JSON retains all values and shape" {
  let first = sample()
  let second = from_json(to_json(first).stringify())
  assert_true(@mat.write_mat(first) == @mat.write_mat(second))
}

///|
test "decimal 64-bit strings are mandatory" {
  let text = "{\"schema\":\"moonmatbridge/1\",\"order\":\"column-major\",\"arrays\":[{\"name\":\"x\",\"dtype\":\"uint64\",\"shape\":[1,1],\"real\":[9007199254740993]}]}"
  assert_true(json_error(text) == "invalid-json")
  let good = text.replace(
    old="[9007199254740993]",
    new="[\"9007199254740993\"]",
  )
  let array = from_json(good)[0]
  match array.value(0) {
    Unsigned(n) => assert_true(n == 9007199254740993UL)
    _ => assert_true(false)
  }
}

///|
test "JSON rejects unknown fields and wrong order" {
  let text = "{\"schema\":\"moonmatbridge/1\",\"order\":\"row-major\",\"arrays\":[]}"
  assert_true(json_error(text) == "invalid-json")
  assert_true(
    json_error(
      "{\"schema\":\"moonmatbridge/1\",\"order\":\"column-major\",\"arrays\":[],\"shpae\":1}",
    ) ==
    "invalid-json",
  )
}

///|
test "negative zero and nonfinite JSON markers preserve semantics" {
  let text = "{\"schema\":\"moonmatbridge/1\",\"order\":\"column-major\",\"arrays\":[{\"name\":\"x\",\"dtype\":\"float64\",\"shape\":[1,4],\"real\":[\"-0\",\"NaN\",\"Infinity\",\"-Infinity\"]}]}"
  let arrays = from_json(text)
  let output = from_json(to_json(arrays).stringify())[0]
  assert_true(output.real == arrays[0].real)
}

///|
test "JSON rejects malformed input excessive depth and wrong imaginary length" {
  assert_true(json_error("{") == "invalid-json")
  let deep = "[".repeat(100) + "0" + "]".repeat(100)
  assert_true(json_error(deep) == "invalid-json")
  let text = "{\"schema\":\"moonmatbridge/1\",\"order\":\"column-major\",\"arrays\":[{\"name\":\"x\",\"dtype\":\"float64\",\"shape\":[1,1],\"real\":[1],\"imag\":[]}]}"
  assert_true(json_error(text) == "invalid-json")
}
