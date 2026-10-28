///|
test "empty selection and root inspection enforce tree budgets" {
  let bytes = write_tree(mixed_tree())
  let tight = { ..default_tree_limits(), max_nodes: 1, }
  let full = error_code(() => ignore(read_tree(bytes, tree_limits=tight)))
  assert_eq(full, "node-limit")
  assert_eq(
    error_code(() => ignore(read_selected(bytes, [], tree_limits=tight))),
    full,
  )
  assert_eq(
    error_code(() => ignore(inspect_roots(bytes, tree_limits=tight))),
    full,
  )
}
