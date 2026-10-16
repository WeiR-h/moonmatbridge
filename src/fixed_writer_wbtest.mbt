///|
test "finished writer buffers stay independent across later writes and metadata edits" {
  let values = mixed_tree()
  let first = write_tree(values)
  let original = first.to_array()
  match values[0] {
    Structure(a) => a.fields[0] = "renamed_samples"
    _ => assert_true(false)
  }
  let second = write_tree(values)
  assert_true(second != first)
  for compressed in [false, true] {
    let later = write_tree(values, compressed~)
    assert_eq(read_tree(later).variables.length(), 2)
    assert_true(first == Bytes::from_array(original))
  }
  match read_tree(first).variables[0] {
    Structure(a) => assert_eq(a.fields[0], "samples")
    _ => assert_true(false)
  }
}
