///|
pub fn published_tree_info(bytes : Bytes) -> String raise @mat.MatError {
  @wire.tree_info(@mat.read_tree(bytes)).stringify()
}
