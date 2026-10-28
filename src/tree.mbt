///|
/// Character payloads retain their storage encoding; multi-byte units are canonical little-endian.
pub(all) enum CharEncoding {
  Int8Text
  UInt8Text
  UInt16Text
  Utf8
  Utf16
  Utf32
} derive(Eq, @debug.Debug)

///|
pub extend CharEncoding with Eq::{equal, not_equal}

///|
pub extend CharEncoding with @debug.Debug::{to_repr}

///|
pub fn CharEncoding::name(self : CharEncoding) -> String {
  match self {
    Int8Text => "miINT8"
    UInt8Text => "miUINT8"
    UInt16Text => "miUINT16"
    Utf8 => "miUTF8"
    Utf16 => "miUTF16"
    Utf32 => "miUTF32"
  }
}

///|
fn CharEncoding::tag_id(self : CharEncoding) -> Int {
  match self {
    Int8Text => 1
    UInt8Text => 2
    UInt16Text => 4
    Utf8 => 16
    Utf16 => 17
    Utf32 => 18
  }
}

///|
fn CharEncoding::width(self : CharEncoding) -> Int {
  match self {
    UInt16Text | Utf16 => 2
    Utf32 => 4
    _ => 1
  }
}

///|
pub(all) struct CharArray {
  name : String
  shape : Array[Int]
  encoding : CharEncoding
  data : Bytes
  is_global : Bool
} derive(@debug.Debug)

///|
pub extend CharArray with @debug.Debug::{to_repr}

///|
/// Children are in column-major order. Nested matrices may have an empty name.
pub(all) struct CellArray {
  name : String
  shape : Array[Int]
  values : Array[MatNode]
  is_global : Bool
} derive(@debug.Debug)

///|
pub extend CellArray with @debug.Debug::{to_repr}

///|
/// Values are element-major, then field order: values[element * fields.length() + field].
/// Some(class_name) represents the documented legacy mxOBJECT class, as data only.
pub(all) struct StructArray {
  name : String
  shape : Array[Int]
  fields : Array[String]
  values : Array[MatNode]
  class_name : String?
  is_global : Bool
} derive(@debug.Debug)

///|
pub extend StructArray with @debug.Debug::{to_repr}

///|
pub(all) enum MatNode {
  Numeric(NumericArray)
  Csc(SparseArray)
  Character(CharArray)
  Cell(CellArray)
  Structure(StructArray)
} derive(@debug.Debug)

///|
pub extend MatNode with @debug.Debug::{to_repr}

///|
pub(all) struct MatTree {
  description : String
  little_endian : Bool
  variables : Array[MatNode]
} derive(@debug.Debug)

///|
pub extend MatTree with @debug.Debug::{to_repr}

///|
pub(all) struct TreeLimits {
  max_depth : Int
  max_nodes : Int
  max_fields : Int
} derive(Eq, @debug.Debug)

///|
pub extend TreeLimits with Eq::{equal, not_equal}

///|
pub extend TreeLimits with @debug.Debug::{to_repr}

///|
pub fn default_tree_limits() -> TreeLimits {
  { max_depth: 64, max_nodes: 65536, max_fields: 4096, }
}

///|
priv struct TreeBudget {
  mut nodes : Int
  mut elements : Int
  mut metadata : Int
  metadata_limit : Int
}

///|
fn validate_tree_limits(tree : TreeLimits) -> Unit raise MatError {
  if tree.max_depth < 1 ||
    tree.max_depth > 128 ||
    tree.max_nodes < 1 ||
    tree.max_nodes > 1048576 ||
    tree.max_fields < 1 ||
    tree.max_fields > 65536 {
    fail(
      "invalid-limits", 0, "Tree depth/nodes/fields exceed documented bounds",
    )
  }
}

///|
fn charge_node(
  budget : TreeBudget,
  depth : Int,
  tree : TreeLimits,
) -> Unit raise MatError {
  if depth > tree.max_depth {
    fail("depth-limit", 0, "Recursive MAT nesting exceeds max_depth")
  }
  if budget.nodes >= tree.max_nodes {
    fail("node-limit", 0, "MAT tree exceeds max_nodes")
  }
  budget.nodes = budget.nodes + 1
}

///|
fn charge_elements(
  budget : TreeBudget,
  count : Int,
  limits : Limits,
) -> Unit raise MatError {
  if count > limits.max_elements - budget.elements {
    fail("element-limit", 0, "Total tree elements exceed max_elements")
  }
  budget.elements = budget.elements + count
}

///|
pub fn MatNode::name(self : MatNode) -> String {
  match self {
    Numeric(a) => a.name
    Csc(a) => a.name
    Character(a) => a.name
    Cell(a) => a.name
    Structure(a) => a.name
  }
}

///|
pub fn MatNode::shape(self : MatNode) -> Array[Int] {
  match self {
    Numeric(a) => a.shape.copy()
    Csc(a) => a.shape.copy()
    Character(a) => a.shape.copy()
    Cell(a) => a.shape.copy()
    Structure(a) => a.shape.copy()
  }
}

///|
pub fn MatTree::get(self : MatTree, name : String) -> MatNode? {
  for item in self.variables {
    if item.name() == name {
      return Some(item)
    }
  }
  None
}

///|
pub fn MatTree::select(
  self : MatTree,
  names : Array[String],
) -> Array[MatNode] raise MatError {
  let seen : Map[String, Bool] = Map([])
  let out = []
  for name in names {
    if seen.contains(name) {
      fail("duplicate-name", 0, "Repeated selection: " + name)
    }
    seen[name] = true
    match self.get(name) {
      Some(item) => out.push(item)
      None => fail("missing-variable", 0, "No variable named: " + name)
    }
  }
  out
}

///|
fn validate_char(
  a : CharArray,
  limits : Limits,
  nested : Bool,
) -> Int raise MatError {
  validate_name(a.name, limits, allow_empty=nested)
  let count = element_count(a.shape, limits, 0)
  if a.data.length() > limits.max_file_bytes {
    fail("file-limit", 0, "Character payload exceeds byte limit")
  }
  validate_char_units(a.data[:], a.encoding, count, true)

  count
}

///|
fn validate_char_units(
  data : BytesView,
  encoding : CharEncoding,
  count : Int,
  little : Bool,
) -> Unit raise MatError {
  if encoding == Utf8 {
    if utf8_scalar_count(data) != count {
      fail(
        "payload-size", 0, "UTF-8 scalar count differs from character dimensions",
      )
    }
  } else {
    if data.length() != count * encoding.width() {
      fail("payload-size", 0, "Character storage does not match dimensions")
    }
    if encoding == Utf32 {
      for i = 0; i < count; i = i + 1 {
        let mut cp = 0UL
        for j = 0; j < 4; j = j + 1 {
          let at = i * 4 + (if little { j } else { 3 - j })
          cp = cp | (data[at].to_uint64() << (j * 8))
        }
        if cp > 1114111UL || (cp >= 55296UL && cp <= 57343UL) {
          fail("invalid-char", i * 4, "UTF-32 requires Unicode scalar values")
        }
      }
    }
  }
}

///|
/// UTF-8 dimensions count Unicode scalars, following SciPy's UTF-8 MAT representation.
pub fn utf8_char_array(
  name : String,
  shape : Array[Int],
  text : String,
  is_global? : Bool = false,
  limits? : Limits = default_limits(),
) -> CharArray raise MatError {
  validate_limits(limits)
  let result : CharArray = {
    name,
    shape: shape.copy(),
    encoding: Utf8,
    data: @utf8.encode(text[:]),
    is_global,
  }
  ignore(validate_char(result, limits, true))
  result
}

///|
fn tree_text(
  bytes : Bytes,
  item : Element,
  limits : Limits,
  empty : Bool,
) -> String raise MatError {
  if item.kind != 1 || item.size > limits.max_name_bytes {
    fail("invalid-name", item.start, "Expected bounded miINT8 name")
  }
  let text = @utf8.decode(bytes[item.start:item.start + item.size]) catch {
    _ => {
      fail("invalid-name", item.start, "Name must be UTF-8")
      ""
    }
  }
  validate_name(text, limits, allow_empty=empty)
  text
}

///|
fn visit_node(
  bytes : Bytes,
  outer : Element,
  little : Bool,
  limits : Limits,
  tree : TreeLimits,
  budget : TreeBudget,
  depth : Int,
  keep : Bool,
) -> MatNode? raise MatError {
  charge_node(budget, depth, tree)
  if outer.kind != 14 {
    fail("invalid-child", outer.start, "Container child must be miMATRIX")
  }
  if outer.size == 0 && depth > 1 {
    if !keep {
      return None
    }
    return Some(
      Numeric({
        name: "",
        dtype: Float64,
        shape: [0, 0],
        real: b"",
        imag: None,
        is_global: false,
      }),
    )
  }
  if budget.metadata_limit > 0 {
    source_charge_metadata(bytes, outer, little, budget)
  }
  let end = outer.start + outer.size
  let flags = tag(bytes, outer.start, end, little)
  if flags.kind != 6 || flags.size != 8 {
    fail("invalid-flags", flags.start, "Expected 8-byte array flags")
  }
  let bits = bits_at(bytes, flags.start, 4, little).to_uint()
  let class = (bits & 255U).reinterpret_as_int()
  if class >= 6 && class <= 15 {
    let (value, count) = numeric_matrix(
      bytes,
      outer,
      little,
      limits,
      nested=depth > 1,
      keep~,
    )
    charge_elements(budget, count, limits)
    return value.map(fn(a) { Numeric(a) })
  }
  if class == 5 {
    let (value, count) = sparse_matrix_read(
      bytes,
      outer,
      little,
      limits,
      nested=depth > 1,
      keep~,
    )
    charge_elements(budget, count, limits)
    return value.map(fn(a) { Csc(a) })
  }
  if class < 1 || class > 4 {
    fail(
      "unsupported-class",
      flags.start,
      "Unsupported MAT class; supported base classes are 1 through 15",
    )
  }
  if (bits & 0xfffffb00U) != 0U ||
    bits_at(bytes, flags.start + 4, 4, little) > 1UL {
    fail(
      "unsupported-flags",
      flags.start,
      "Containers and char support only the global flag",
    )
  }
  let dims = tag(bytes, flags.next, end, little)
  if dims.kind != 5 ||
    dims.size < 8 ||
    dims.size % 4 != 0 ||
    dims.size / 4 > limits.max_dimensions {
    fail("invalid-shape", dims.start, "Expected bounded miINT32 dimensions")
  }
  let shape = Array::makei(dims.size / 4, i => {
    bits_at(bytes, dims.start + i * 4, 4, little).to_uint().reinterpret_as_int()
  })
  let count = element_count(shape, limits, dims.start)
  charge_elements(budget, count, limits)
  let name_tag = tag(bytes, dims.next, end, little)
  let name = tree_text(bytes, name_tag, limits, depth > 1)
  let is_global = (bits & 1024U) != 0U
  let mut pos = name_tag.next
  if class == 4 {
    let data = tag(bytes, pos, end, little)
    let encoding = match data.kind {
      1 => Int8Text
      2 => UInt8Text
      4 => UInt16Text
      16 => Utf8
      17 => Utf16
      18 => Utf32
      _ => {
        fail(
          "unsupported-char-encoding",
          data.start,
          "Unsupported character storage tag",
        )
        Utf8
      }
    }
    if data.next != end {
      fail("trailing-matrix-data", data.next, "Unexpected character data")
    }
    if data.size > limits.max_file_bytes {
      fail("file-limit", 0, "Character payload exceeds byte limit")
    }
    validate_char_units(
      bytes[data.start:data.start + data.size],
      encoding,
      count,
      little,
    )
    if !keep {
      return None
    }
    let width = encoding.width()
    let raw = if little || width == 1 {
      payload(bytes, data)
    } else {
      Bytes::makei(data.size, i => {
        bytes[data.start + i / width * width + width - 1 - i % width]
      })
    }
    return Some(Character({ name, shape, encoding, data: raw, is_global, }))
  }

  let class_name = if class == 3 {
    let item = tag(bytes, pos, end, little)
    pos = item.next
    Some(tree_text(bytes, item, limits, false))
  } else {
    None
  }
  let fields : Array[String] = []
  if class == 2 || class == 3 {
    let width_tag = tag(bytes, pos, end, little)
    if width_tag.kind != 5 || width_tag.size != 4 {
      fail("invalid-fields", pos, "Field-name length must be one miINT32")
    }
    let width = bits_at(bytes, width_tag.start, 4, little)
    if width < 1UL || width > (limits.max_name_bytes + 1).to_uint64() {
      fail("invalid-fields", width_tag.start, "Field-name width exceeds bound")
    }
    let width = width.to_int()
    let table = tag(bytes, width_tag.next, end, little)
    if table.kind != 1 ||
      table.size % width != 0 ||
      table.size / width > tree.max_fields {
      fail(
        "invalid-fields",
        table.start,
        "Invalid or excessive field-name table",
      )
    }
    let seen : Map[String, Bool] = Map([])
    for i = 0; i < table.size / width; i = i + 1 {
      let start = table.start + i * width
      let mut length = 0
      while length < width && bytes[start + length] != b'\x00' {
        length = length + 1
      }
      if length == width {
        fail("invalid-fields", start, "Field name needs NUL terminator")
      }
      for j = length; j < width; j = j + 1 {
        if bytes[start + j] != b'\x00' {
          fail("invalid-fields", start + j, "Nonzero field-name padding")
        }
      }
      let field = tree_text(
        bytes,
        { kind: 1, start, size: length, next: start + width, },
        limits,
        false,
      )
      if seen.contains(field) {
        fail("duplicate-field", start, "Duplicate struct field")
      }
      seen[field] = true
      fields.push(field)
    }
    pos = table.next
  }
  let multiplier = if class == 1 { 1 } else { fields.length() }
  if multiplier > 0 && count > (tree.max_nodes - budget.nodes) / multiplier {
    fail("node-limit", pos, "Container child count exceeds max_nodes")
  }
  let values : Array[MatNode] = []
  for i = 0; i < count * multiplier; i = i + 1 {
    let child = tag(bytes, pos, end, little)
    let value = visit_node(
      bytes,
      child,
      little,
      limits,
      tree,
      budget,
      depth + 1,
      keep,
    )
    if value is Some(node) {
      values.push(node)
    }
    pos = child.next
  }
  if pos != end {
    fail(
      "trailing-matrix-data", pos, "Container child count does not match dimensions/fields",
    )
  }
  if !keep {
    return None
  }
  if class == 1 {
    Some(Cell({ name, shape, values, is_global, }))
  } else {
    Some(Structure({ name, shape, fields, values, class_name, is_global, }))
  }
}

///|
fn element_size(length : Int) -> Int {
  8 + length + (8 - length % 8) % 8
}

///|
fn node_size(
  node : MatNode,
  limits : Limits,
  tree : TreeLimits,
  budget : TreeBudget,
  depth : Int,
  planned : Array[Int],
) -> Int raise MatError {
  let plan_index = planned.length()
  planned.push(0)
  charge_node(budget, depth, tree)
  validate_name(node.name(), limits, allow_empty=depth > 1)
  let shape = node.shape()
  let mut size = 16 +
    element_size(shape.length() * 4) +
    element_size(@utf8.encode(node.name()[:]).length())
  let mut count = 0
  match node {
    Numeric(a) => {
      count = validate_array(a, limits, allow_empty=depth > 1)
      size = size + element_size(a.real.length())
      if a.imag is Some(imag) {
        size = size + element_size(imag.length())
      }
    }
    Csc(a) => {
      count = validate_sparse(a, limits, allow_empty=depth > 1)
      size = size +
        element_size(a.row_indices.length() * 4) +
        element_size(a.col_ptrs.length() * 4) +
        element_size(a.real.length())
      if a.imag is Some(imag) {
        size = size + element_size(imag.length())
      }
    }
    Character(a) => {
      count = validate_char(a, limits, depth > 1)
      size = size + element_size(a.data.length())
    }
    Cell(a) => {
      count = element_count(a.shape, limits, 0)
      if a.values.length() != count {
        fail("payload-size", 0, "Cell child count differs from dimensions")
      }
      for child in a.values {
        let bytes = node_size(child, limits, tree, budget, depth + 1, planned) +
          8
        if bytes > limits.max_file_bytes - size {
          fail("file-limit", 0, "Encoded tree exceeds byte limit")
        }
        size = size + bytes
      }
    }
    Structure(a) => {
      count = element_count(a.shape, limits, 0)
      if a.fields.length() > tree.max_fields {
        fail("invalid-fields", 0, "Too many struct fields")
      }
      if a.fields.length() > 0 && count > tree.max_nodes / a.fields.length() {
        fail("node-limit", 0, "Struct children exceed node limit")
      }
      if a.values.length() != count * a.fields.length() {
        fail(
          "payload-size", 0, "Struct child count differs from dimensions/fields",
        )
      }
      let seen : Map[String, Bool] = Map([])
      let mut width = 1
      for field in a.fields {
        validate_name(field, limits)
        if seen.contains(field) {
          fail("duplicate-field", 0, "Duplicate struct field")
        }
        seen[field] = true
        let required = @utf8.encode(field[:]).length() + 1
        if required > width {
          width = required
        }
      }
      if a.fields.length() > 0 &&
        width > limits.max_file_bytes / a.fields.length() {
        fail("file-limit", 0, "Field table exceeds byte limit")
      }
      // Canonical field-name length uses the 8-byte small data element.
      size = size + 8 + element_size(width * a.fields.length())
      if a.class_name is Some(class_name) {
        validate_name(class_name, limits)
        size = size + element_size(@utf8.encode(class_name[:]).length())
      }
      for child in a.values {
        let bytes = node_size(child, limits, tree, budget, depth + 1, planned) +
          8
        if bytes > limits.max_file_bytes - size {
          fail("file-limit", 0, "Encoded tree exceeds byte limit")
        }
        size = size + bytes
      }
    }
  }
  charge_elements(budget, count, limits)
  if size > limits.max_file_bytes - 8 {
    fail("file-limit", 0, "Encoded matrix exceeds byte limit")
  }
  planned[plan_index] = size
  size
}
