///|
test "transform pipeline composes raw-byte operations without mutating input" {
  let source = [
    @mat.numeric_array("x", @mat.UInt64, [2, 3], [
      Unsigned(1UL),
      Unsigned(2UL),
      Unsigned(3UL),
      Unsigned(4UL),
      Unsigned(9007199254740993UL),
      Unsigned(18446744073709551615UL),
    ]),
  ]
  let text = "{\"schema\":\"moonmatbridge/transform/1\",\"operations\":[{\"op\":\"gather\",\"name\":\"x\",\"axis\":1,\"indices\":[2,0]},{\"op\":\"permute\",\"name\":\"x\",\"axes\":[1,0]},{\"op\":\"concat\",\"name\":\"y\",\"inputs\":[\"x\",\"x\"],\"axis\":0}]}"
  let out = transform(source, text)
  assert_eq(source[0].shape, [2, 3])
  assert_eq(out[0].shape, [2, 2])
  assert_eq(out[1].shape, [4, 2])
  assert_true(out[0].value(0) is Unsigned(9007199254740993UL))
  assert_true(out[1].value(6) is Unsigned(18446744073709551615UL))
}

///|
test "transform rejects typos missing variables duplicate outputs and excessive operations" {
  let source = sample()
  let check = fn(text : String) {
    ignore(transform(source, text)) catch {
      error => return error.code()
    }
    "no-error"
  }
  assert_eq(
    check(
      "{\"schema\":\"moonmatbridge/transform/1\",\"operations\":[{\"op\":\"reshape\",\"name\":\"temperature\",\"shape\":[6,1],\"shpae\":[]}]}",
    ),
    "invalid-json",
  )
  assert_eq(
    check(
      "{\"schema\":\"moonmatbridge/transform/1\",\"operations\":[{\"op\":\"reshape\",\"name\":\"absent\",\"shape\":[6,1]}]}",
    ),
    "missing-variable",
  )
  assert_eq(
    check(
      "{\"schema\":\"moonmatbridge/transform/1\",\"operations\":[{\"op\":\"concat\",\"name\":\"temperature\",\"inputs\":[],\"axis\":0}]}",
    ),
    "duplicate-name",
  )
  let many = "{\"op\":\"reshape\",\"name\":\"temperature\",\"shape\":[6,1]},".repeat(
      256,
    ) +
    "{\"op\":\"reshape\",\"name\":\"temperature\",\"shape\":[6,1]}"
  assert_eq(
    check(
      "{\"schema\":\"moonmatbridge/transform/1\",\"operations\":[" + many + "]}",
    ),
    "invalid-json",
  )
}

///|
test "mixed transform preserves CSC and rejects sparse output shadowing" {
  let a = @mat.numeric_array("a", @mat.Float64, [1, 1], [Floating(1.0)])
  let b = @mat.numeric_array(
    "b",
    @mat.Float64,
    [1, 1],
    [Floating(2.0)],
    is_global=true,
  ).to_sparse()
  let source = [@mat.Dense(a), @mat.Sparse(b)]
  let valid = "{\"schema\":\"moonmatbridge/transform/1\",\"operations\":[{\"op\":\"gather\",\"name\":\"a\",\"axis\":0,\"indices\":[0,0]}]}"
  let out = transform_document(source, valid)
  assert_true(@mat.write_document([out[1]]) == @mat.write_document([source[1]]))
  let invalid = "{\"schema\":\"moonmatbridge/transform/1\",\"operations\":[{\"op\":\"concat\",\"name\":\"b\",\"inputs\":[\"a\",\"a\"],\"axis\":0}]}"
  let error = try {
    ignore(transform_document(source, invalid))
    "no-error"
  } catch {
    e => e.code()
  }
  assert_eq(error, "duplicate-name")
  assert_eq(source[0].name(), "a")
}
