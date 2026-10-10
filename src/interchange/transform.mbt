///|
fn integer(value : Json) -> Int raise @mat.MatError {
  match value {
    Number(n, ..) => {
      if n.is_nan() || n.is_inf() || n.trunc() != n || n < -2147483648.0 || n > 2147483647.0 {
        invalid("Expected bounded integer")
      }
      n.to_int()
    }
    _ => { invalid("Expected integer"); 0 }
  }
}

///|
fn integers(value : Json) -> Array[Int] raise @mat.MatError {
  array(value).map(integer)
}

///|
fn lookup(arrays : Array[@mat.NumericArray], name : String) -> Int raise @mat.MatError {
  for i, item in arrays {
    if item.name == name { return i }
  }
  raise @mat.MatError("missing-variable", 0, "No variable named: " + name)
}

///|
/// Execute a strict, bounded raw-byte transformation plan. Source arrays are never mutated.
pub fn transform(
  arrays : Array[@mat.NumericArray],
  plan : String,
  limits? : @mat.Limits = @mat.default_limits(),
) -> Array[@mat.NumericArray] raise @mat.MatError {
  if plan.length() > limits.max_file_bytes { invalid("Transform plan exceeds byte limit") }
  let document = bounded_parse(plan) catch { _ => { invalid("Malformed transform plan"); Json::null() } }
  let root = object(document)
  reject_unknown(root, ["schema", "operations"])
  if string(required(root, "schema")) != "moonmatbridge/transform/1" { invalid("Expected moonmatbridge/transform/1") }
  let operations = array(required(root, "operations"))
  if operations.length() > 256 { invalid("At most 256 transform operations") }
  let out = arrays.copy()
  for operation in operations {
    let fields = object(operation)
    let op = string(required(fields, "op"))
    let name = string(required(fields, "name"))
    if op == "concat" {
      reject_unknown(fields, ["op", "name", "inputs", "axis"])
      for item in out {
        if item.name == name { raise @mat.MatError("duplicate-name", 0, "Concat target already exists: " + name) }
      }
      let inputs = array(required(fields, "inputs")).map(value => out[lookup(out, string(value))])
      if out.length() >= limits.max_variables { invalid("Too many transform outputs") }
      out.push(@mat.concat_arrays(name, inputs, integer(required(fields, "axis")), limits~))
    } else {
      let index = lookup(out, name)
      let item = out[index]
      let changed = match op {
        "slice" => {
          reject_unknown(fields, ["op", "name", "starts", "counts", "steps"])
          let steps = fields.get("steps").map(integers)
          item.slice(integers(required(fields, "starts")), integers(required(fields, "counts")), steps?, limits~)
        }
        "gather" => {
          reject_unknown(fields, ["op", "name", "axis", "indices"])
          item.gather_axis(integer(required(fields, "axis")), integers(required(fields, "indices")), limits~)
        }
        "reshape" => {
          reject_unknown(fields, ["op", "name", "shape"])
          item.reshape(integers(required(fields, "shape")), limits~)
        }
        "permute" => {
          reject_unknown(fields, ["op", "name", "axes"])
          item.permute_axes(integers(required(fields, "axes")), limits~)
        }
        _ => { invalid("Unknown transform operation: " + op); item }
      }
      out[index] = changed
    }
  }
  // Revalidate the aggregate, not only each transformed variable.
  @mat.validate_document(out.map(fn(a) { @mat.Dense(a) }), limits~)
  out
}
