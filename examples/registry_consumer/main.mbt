///|
fn main {
  try {
    let array = @mat.numeric_array("signal", @mat.Float64, [2, 1], [Floating(1.0), Floating(2.0)])
    let document = @mat.read_document(@mat.write_mat([array]))
    let snapshot = @wire.to_snapshot(document.variables)
    let file = @mat.read_mat(@mat.write_document(@wire.from_snapshot(snapshot)))
    let restored = file.get("signal").unwrap()
    println("MoonMatBridge " + @mat.version() + ": signal has " + restored.length().to_string() + " values")
  } catch {
    error => abort(error.code())
  }
}
