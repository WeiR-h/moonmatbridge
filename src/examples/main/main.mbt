///|
/// This example uses the library directly and works on JS, wasm-gc and native.
fn main {
  try {
    let input = @wire.sample()
    let bytes = @mat.write_mat(input)
    let file = @mat.read_mat(bytes)
    println(@wire.info(file).stringify(indent=2))
    let spectrum = file.arrays[1]
    let coordinate = spectrum.index([1, 0])
    println(
      "Second spectrum value: \{spectrum.value(coordinate).to_repr()}, imaginary \{spectrum.value(coordinate, imaginary=true).to_repr()}",
    )
  } catch {
    error => println(@wire.error_json(error).stringify())
  }
}
