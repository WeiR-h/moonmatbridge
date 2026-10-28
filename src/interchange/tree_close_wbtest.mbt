///|
test "tree close options and independent report schema are strict" {
  let value = @mat.Numeric(
    @mat.numeric_array("x", @mat.Float64, [1, 1], [@mat.Floating(1.0)]),
  )
  let tree : @mat.MatTree = {
    description: "",
    little_endian: true,
    variables: [value],
  }
  let report = compare_tree_text(
    tree, tree, "{\"atol\":0.125,\"rtol\":0.25,\"equal_nan\":true,\"max_samples\":0}",
  )
  assert_true(report.within_tolerance && report.exact_equal)
  let json = object(tree_close_json(report))
  assert_eq(string(required(json, "schema")), "moonmatbridge/tree-close/1")
  assert_true(!json.contains("content_equal"))
  for
    options in [
      "[]", "{\"atoll\":1}", "{\"equal_nan\":1}", "{\"max_samples\":1.5}", "{\"max_samples\":257}",
      "{\"atol\":-1}", "{\"rtol\":true}", "{\"rtol\":1e999}",
    ] {
    let failed = try {
      ignore(compare_tree_text(tree, tree, options))
      false
    } catch {
      _ => true
    }
    assert_true(failed)
  }
}
