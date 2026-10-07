///|
/// Select variables in requested order, rejecting missing or ambiguous names.
pub fn MatFile::select(
  self : MatFile,
  names : Array[String],
  limits? : Limits = default_limits(),
) -> Array[NumericArray] raise MatError {
  validate_limits(limits)
  if self.arrays.length() > limits.max_variables || names.length() > limits.max_variables {
    fail("variable-limit", 0, "Too many variables")
  }
  let available : Map[String, NumericArray] = Map([])
  for array in self.arrays {
    if available.contains(array.name) {
      fail("duplicate-name", 0, "Ambiguous source variable: " + array.name)
    }
    available[array.name] = array
  }
  let chosen : Map[String, Bool] = Map([])
  let result = []
  let mut elements = 0
  for name in names {
    if chosen.contains(name) {
      fail("duplicate-name", 0, "Variable requested twice: " + name)
    }
    chosen[name] = true
    match available.get(name) {
      Some(array) => {
        let count = validate_array(array, limits)
        if count > limits.max_elements - elements {
          fail("element-limit", 0, "Selected arrays exceed total element limit")
        }
        elements = elements + count
        result.push(array)
      }
      None => fail("missing-variable", 0, "No variable named: " + name)
    }
  }
  result
}
