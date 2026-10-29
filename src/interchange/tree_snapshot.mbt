///|
priv struct SnapshotBudget {
  mut encoded : Int32
  mut bytes : Int32
  mut nodes : Int32
  mut elements : Int32
  mut fields : Int32
}

///|
fn snapshot_charge(
  budget : SnapshotBudget,
  count : Int32,
  limits : @mat.Limits,
) -> Unit raise @mat.MatError {
  let maximum = if limits.max_file_bytes < limits.max_expanded_bytes {
    limits.max_file_bytes
  } else {
    limits.max_expanded_bytes
  }
  if count < 0 || count > maximum - budget.bytes {
    raise @mat.MatError(
      "expanded-limit", 0, "Snapshot cumulative payload exceeds byte limit",
    )
  }
  budget.bytes = budget.bytes + count
}

///|
fn snapshot_estimate(
  budget : SnapshotBudget,
  count : Int32,
  limits : @mat.Limits,
) -> Unit raise @mat.MatError {
  if count < 0 || count > limits.max_file_bytes - budget.encoded {
    invalid("Encoded tree snapshot exceeds byte limit")
  }
  budget.encoded = budget.encoded + count
}

///|
fn snapshot_raw(
  node : @mat.MatNode,
  budget : SnapshotBudget,
  limits : @mat.Limits,
) -> Unit raise @mat.MatError {
  snapshot_charge(budget, @utf8.encode(node.name()[:]).length(), limits)
  match node {
    Numeric(a) => {
      snapshot_charge(budget, a.real.length(), limits)
      if a.imag is Some(b) {
        snapshot_charge(budget, b.length(), limits)
      }
    }
    Csc(a) => {
      snapshot_charge(budget, a.row_indices.length() * 4, limits)
      snapshot_charge(budget, a.col_ptrs.length() * 4, limits)
      snapshot_charge(budget, a.real.length(), limits)
      if a.imag is Some(b) {
        snapshot_charge(budget, b.length(), limits)
      }
    }
    Character(a) => snapshot_charge(budget, a.data.length(), limits)
    Cell(_) => ()
    Structure(a) => {
      for field in a.fields {
        snapshot_charge(budget, @utf8.encode(field[:]).length(), limits)
      }
      if a.class_name is Some(name) {
        snapshot_charge(budget, @utf8.encode(name[:]).length(), limits)
      }
    }
  }
}

///|
fn snapshot_visit(
  budget : SnapshotBudget,
  depth : Int32,
  tree : @mat.TreeLimits,
) -> Unit raise @mat.MatError {
  if depth > tree.max_depth {
    raise @mat.MatError("depth-limit", 0, "Snapshot nesting exceeds max_depth")
  }
  if budget.nodes >= tree.max_nodes {
    raise @mat.MatError("node-limit", 0, "Snapshot exceeds max_nodes")
  }
  budget.nodes = budget.nodes + 1
}

///|
fn snapshot_fields(
  budget : SnapshotBudget,
  count : Int32,
  tree : @mat.TreeLimits,
) -> Unit raise @mat.MatError {
  if count > tree.max_fields - budget.fields {
    raise @mat.MatError(
      "invalid-fields", 0, "Snapshot cumulative fields exceed max_fields",
    )
  }
  budget.fields = budget.fields + count
}

///|
fn snapshot_shape(
  shape : Array[Int32],
  budget : SnapshotBudget,
  limits : @mat.Limits,
  sparse : Bool,
) -> Unit raise @mat.MatError {
  if shape.length() < 2 ||
    shape.length() > limits.max_dimensions ||
    shape.any(n => n < 0) {
    invalid("Snapshot requires bounded nonnegative dimensions")
  }
  if sparse {
    return
  }
  let mut count = if shape.contains(0) { 0 } else { 1 }
  for size in shape {
    if count != 0 && size > limits.max_elements / count {
      raise @mat.MatError(
        "element-limit", 0, "Snapshot shape exceeds element limit",
      )
    }
    count = count * size
  }
  if count > limits.max_elements - budget.elements {
    raise @mat.MatError(
      "element-limit", 0, "Snapshot cumulative elements exceed limit",
    )
  }
  budget.elements = budget.elements + count
}

///|
fn snapshot_preflight(
  node : @mat.MatNode,
  budget : SnapshotBudget,
  limits : @mat.Limits,
  tree : @mat.TreeLimits,
  depth : Int32,
) -> Unit raise @mat.MatError {
  snapshot_visit(budget, depth, tree)
  snapshot_raw(node, budget, limits)
  // Bound escaped JSON metadata and hex payloads before constructing them.
  snapshot_estimate(
    budget,
    256 + @utf8.encode(node.name()[:]).length() * 6 + node.shape().length() * 12,
    limits,
  )
  match node {
    Numeric(a) => {
      snapshot_estimate(budget, a.real.length() * 2, limits)
      if a.imag is Some(b) {
        snapshot_estimate(budget, b.length() * 2, limits)
      }
    }
    Csc(a) => {
      snapshot_estimate(
        budget,
        (a.row_indices.length() + a.col_ptrs.length()) * 12,
        limits,
      )
      snapshot_estimate(budget, a.real.length() * 2, limits)
      if a.imag is Some(b) {
        snapshot_estimate(budget, b.length() * 2, limits)
      }
    }
    Character(a) => snapshot_estimate(budget, a.data.length() * 2, limits)
    Cell(a) =>
      for child in a.values {
        snapshot_preflight(child, budget, limits, tree, depth + 1)
      }
    Structure(a) => {
      snapshot_fields(budget, a.fields.length(), tree)
      for field in a.fields {
        snapshot_estimate(
          budget,
          @utf8.encode(field[:]).length() * 6 + 3,
          limits,
        )
      }
      if a.class_name is Some(name) {
        snapshot_estimate(budget, @utf8.encode(name[:]).length() * 6, limits)
      }
      for child in a.values {
        snapshot_preflight(child, budget, limits, tree, depth + 1)
      }
    }
  }
}

///|
fn tree_snapshot_node(node : @mat.MatNode) -> Json {
  let global = match node {
    Numeric(a) => a.is_global
    Csc(a) => a.is_global
    Character(a) => a.is_global
    Cell(a) => a.is_global
    Structure(a) => a.is_global
  }
  let fields : Map[String, Json] = Map([
    ("name", Json::string(node.name())),
    ("shape", Json::array(node.shape().map(n => Json::number(n.to_double())))),
    ("global", Json::boolean(global)),
  ])
  match node {
    Numeric(a) => {
      fields["storage"] = "dense"
      fields["dtype"] = Json::string(a.dtype.name())
      fields["real_hex"] = Json::string(hex(a.real))
      fields["imag_hex"] = a.imag
        .map(b => Json::string(hex(b)))
        .unwrap_or(Json::null())
    }
    Csc(a) => {
      fields["storage"] = "csc"
      fields["dtype"] = Json::string(a.dtype.name())
      fields["real_hex"] = Json::string(hex(a.real))
      fields["imag_hex"] = a.imag
        .map(b => Json::string(hex(b)))
        .unwrap_or(Json::null())
      fields["row_indices"] = Json::array(
        a.row_indices.map(n => Json::number(n.to_double())),
      )
      fields["col_ptrs"] = Json::array(
        a.col_ptrs.map(n => Json::number(n.to_double())),
      )
      fields["nzmax"] = Json::number(a.nzmax.to_double())
    }
    Character(a) => {
      fields["storage"] = "char"
      fields["encoding"] = Json::string(a.encoding.name())
      fields["data_hex"] = Json::string(hex(a.data))
    }
    Cell(a) => {
      fields["storage"] = "cell"
      fields["values"] = Json::array(a.values.map(tree_snapshot_node))
    }
    Structure(a) => {
      fields["storage"] = if a.class_name is Some(_) {
        "object"
      } else {
        "struct"
      }
      fields["class_name"] = a.class_name
        .map(Json::string)
        .unwrap_or(Json::null())
      fields["fields"] = Json::array(a.fields.map(Json::string))
      fields["values"] = Json::array(a.values.map(tree_snapshot_node))
    }
  }
  Json::object(fields)
}

///|
pub fn to_tree_snapshot(
  variables : Array[@mat.MatNode],
  limits~ : @mat.Limits = @mat.default_limits(),
  tree_limits~ : @mat.TreeLimits = @mat.default_tree_limits(),
) -> String raise @mat.MatError {
  @mat.validate_tree(variables, limits~, tree_limits~)
  let budget : SnapshotBudget = {
    bytes: 0,
    encoded: 0,
    nodes: 0,
    elements: 0,
    fields: 0,
  }
  snapshot_estimate(budget, 128, limits)
  for node in variables {
    snapshot_preflight(node, budget, limits, tree_limits, 1)
  }
  let text = (
    {
      "schema": "moonmatbridge/tree-snapshot/1",
      "order": "column-major",
      "byte_order": "little",
      "variables": Json::array(variables.map(tree_snapshot_node)),
    } : Json).stringify()
  if @utf8.encode(text[:]).length() > limits.max_file_bytes {
    invalid("Encoded tree snapshot exceeds byte limit")
  }
  text
}

///|
fn snapshot_text(
  value : Json,
  budget : SnapshotBudget,
  limits : @mat.Limits,
) -> String raise @mat.MatError {
  let text = string(value)
  let bytes = @utf8.encode(text[:]).length()
  if bytes > limits.max_name_bytes {
    invalid("Snapshot name exceeds max_name_bytes")
  }
  snapshot_charge(budget, bytes, limits)
  text
}

///|
fn snapshot_unhex(
  value : Json,
  budget : SnapshotBudget,
  limits : @mat.Limits,
) -> Bytes raise @mat.MatError {
  let text = string(value)
  if text.length() % 2 != 0 {
    invalid("Hex payload requires complete pairs")
  }
  snapshot_charge(budget, text.length() / 2, limits)
  unhex(value, limits.max_file_bytes)
}

///|
fn snapshot_decode_node(
  value : Json,
  budget : SnapshotBudget,
  limits : @mat.Limits,
  tree : @mat.TreeLimits,
  depth : Int32,
) -> @mat.MatNode raise @mat.MatError {
  snapshot_visit(budget, depth, tree)
  let fields = object(value)
  let storage = string(required(fields, "storage"))
  let allowed = ["name", "storage", "shape", "global"]
  match storage {
    "dense" =>
      for s in ["dtype", "real_hex", "imag_hex"] {
        allowed.push(s)
      }
    "csc" =>
      for
        s in [
          "dtype", "real_hex", "imag_hex", "row_indices", "col_ptrs", "nzmax",
        ] {
        allowed.push(s)
      }
    "char" => {
      allowed.push("encoding")
      allowed.push("data_hex")
    }
    "cell" => allowed.push("values")
    "struct" | "object" => {
      allowed.push("fields")
      allowed.push("class_name")
      allowed.push("values")
    }
    _ => invalid("Unknown tree snapshot storage")
  }
  reject_unknown(fields, allowed)
  let name = snapshot_text(required(fields, "name"), budget, limits)
  let shape = bounded_integers(required(fields, "shape"), limits.max_dimensions)
  snapshot_shape(shape, budget, limits, storage == "csc")
  let global = match required(fields, "global") {
    True => true
    False => false
    _ => {
      invalid("Global requires boolean")
      false
    }
  }
  match storage {
    "dense" => {
      let dtype = @mat.dtype_from_name(string(required(fields, "dtype")))
      let real = snapshot_unhex(required(fields, "real_hex"), budget, limits)
      let imag = match required(fields, "imag_hex") {
        Null => None
        value => Some(snapshot_unhex(value, budget, limits))
      }
      let array = @mat.raw_array(
        "_",
        dtype,
        shape,
        real,
        imag?,
        is_global=global,
        limits~,
      )
      @mat.Numeric({ ..array, name, })
    }
    "csc" => {
      let dtype = @mat.dtype_from_name(string(required(fields, "dtype")))
      let row_values = array(required(fields, "row_indices"))
      let columns = array(required(fields, "col_ptrs"))
      if row_values.length() > limits.max_elements - budget.elements {
        raise @mat.MatError(
          "element-limit", 0, "Snapshot CSC slots exceed cumulative elements",
        )
      }
      budget.elements = budget.elements + row_values.length()
      if columns.length() > limits.max_elements {
        invalid("CSC pointers exceed element limit")
      }
      snapshot_charge(budget, row_values.length() * 4, limits)
      snapshot_charge(budget, columns.length() * 4, limits)
      let rows = row_values.map(integer)
      let cols = columns.map(integer)
      let real = snapshot_unhex(required(fields, "real_hex"), budget, limits)
      let imag = match required(fields, "imag_hex") {
        Null => None
        value => Some(snapshot_unhex(value, budget, limits))
      }
      let array = @mat.raw_sparse_array(
        "_",
        dtype,
        shape,
        rows,
        cols,
        real,
        imag?,
        nzmax=integer(required(fields, "nzmax")),
        is_global=global,
        limits~,
      )
      @mat.Csc({ ..array, name, })
    }
    "char" => {
      let encoding : @mat.CharEncoding = match
        string(required(fields, "encoding")) {
        "miINT8" => @mat.Int8Text
        "miUINT8" => @mat.UInt8Text
        "miUINT16" => @mat.UInt16Text
        "miUTF8" => @mat.Utf8
        "miUTF16" => @mat.Utf16
        "miUTF32" => @mat.Utf32
        _ => {
          invalid("Unknown character storage encoding")
          @mat.Utf8
        }
      }
      @mat.Character({
        name,
        shape,
        encoding,
        data: snapshot_unhex(required(fields, "data_hex"), budget, limits),
        is_global: global,
      })
    }
    "cell" => {
      let values = array(required(fields, "values"))
      if values.length() > tree.max_nodes - budget.nodes {
        raise @mat.MatError(
          "node-limit", 0, "Cell snapshot children exceed node budget",
        )
      }
      @mat.Cell({
        name,
        shape,
        is_global: global,
        values: values.map(v => {
          snapshot_decode_node(v, budget, limits, tree, depth + 1)
        }),
      })
    }
    _ => {
      let names = array(required(fields, "fields"))
      snapshot_fields(budget, names.length(), tree)
      let names = names.map(v => snapshot_text(v, budget, limits))
      let class_name = match required(fields, "class_name") {
        Null => None
        v => Some(snapshot_text(v, budget, limits))
      }
      if (class_name is Some(_)) != (storage == "object") {
        invalid("Object storage requires a class name; struct requires null")
      }
      let values = array(required(fields, "values"))
      if values.length() > tree.max_nodes - budget.nodes {
        raise @mat.MatError(
          "node-limit", 0, "Struct snapshot children exceed node budget",
        )
      }
      @mat.Structure({
        name,
        shape,
        fields: names,
        class_name,
        is_global: global,
        values: values.map(v => {
          snapshot_decode_node(v, budget, limits, tree, depth + 1)
        }),
      })
    }
  }
}

///|
#warnings("-deprecated")
fn bounded_tree_parse(text : String, depth : Int32) -> Json raise {
  @json.parse(text[:], max_nesting_depth=depth * 2 + 8)
}

///|
pub fn from_tree_snapshot(
  text : String,
  limits~ : @mat.Limits = @mat.default_limits(),
  tree_limits~ : @mat.TreeLimits = @mat.default_tree_limits(),
) -> Array[@mat.MatNode] raise @mat.MatError {
  @mat.validate_tree([], limits~, tree_limits~)
  if text.length() > limits.max_file_bytes ||
    @utf8.encode(text[:]).length() > limits.max_file_bytes {
    invalid("Tree snapshot exceeds input byte limit")
  }
  let parsed = bounded_tree_parse(text, tree_limits.max_depth) catch {
    _ => {
      invalid("Malformed tree snapshot JSON or excessive nesting")
      Json::null()
    }
  }
  let root = object(parsed)
  reject_unknown(root, ["schema", "order", "byte_order", "variables"])
  if string(required(root, "schema")) != "moonmatbridge/tree-snapshot/1" ||
    string(required(root, "order")) != "column-major" ||
    string(required(root, "byte_order")) != "little" {
    invalid("Expected canonical tree-snapshot/1")
  }
  let entries = array(required(root, "variables"))
  if entries.length() > limits.max_variables {
    raise @mat.MatError("variable-limit", 0, "Too many tree snapshot roots")
  }
  let budget : SnapshotBudget = {
    bytes: 0,
    encoded: 0,
    nodes: 0,
    elements: 0,
    fields: 0,
  }
  let variables = entries.map(v => {
    snapshot_decode_node(v, budget, limits, tree_limits, 1)
  })
  @mat.validate_tree(variables, limits~, tree_limits~)
  variables
}
