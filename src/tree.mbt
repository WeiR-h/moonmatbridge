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
  if a.encoding == Utf8 {
    let text = @utf8.decode(a.data[:]) catch {
      _ => {
        fail("invalid-char", 0, "Malformed UTF-8 character payload")
        ""
      }
    }
    if text.iter().count() != count {
      fail(
        "payload-size", 0, "UTF-8 scalar count differs from character dimensions",
      )
    }
  } else {
    if a.data.length() != count * a.encoding.width() {
      fail("payload-size", 0, "Character storage does not match dimensions")
    }
    if a.encoding == Utf32 {
      for i = 0; i < count; i = i + 1 {
        let cp = bits_at(a.data, i * 4, 4, true)
        if cp > 1114111UL || (cp >= 55296UL && cp <= 57343UL) {
          fail("invalid-char", i * 4, "UTF-32 requires Unicode scalar values")
        }
      }
    }
  }
  count
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
fn read_node(
  bytes : Bytes,
  outer : Element,
  little : Bool,
  limits : Limits,
  tree : TreeLimits,
  budget : TreeBudget,
  depth : Int,
) -> MatNode raise MatError {
  charge_node(budget, depth, tree)
  if outer.kind != 14 {
    fail("invalid-child", outer.start, "Container child must be miMATRIX")
  }
  if outer.size == 0 && depth > 1 {
    return Numeric({
      name: "",
      dtype: Float64,
      shape: [0, 0],
      real: b"",
      imag: None,
      is_global: false,
    })
  }
  let end = outer.start + outer.size
  let flags = tag(bytes, outer.start, end, little)
  if flags.kind != 6 || flags.size != 8 {
    fail("invalid-flags", flags.start, "Expected 8-byte array flags")
  }
  let bits = bits_at(bytes, flags.start, 4, little).to_uint()
  let class = (bits & 255U).reinterpret_as_int()
  if class >= 6 && class <= 15 {
    let a = matrix(bytes, outer, little, limits, nested=depth > 1)
    charge_elements(budget, a.length(), limits)
    return Numeric(a)
  }
  if class == 5 {
    let a = sparse_matrix(bytes, outer, little, limits, nested=depth > 1)
    charge_elements(budget, a.row_indices.length(), limits)
    return Csc(a)
  }
  if class < 1 || class > 4 {
    fail(
      "unsupported-class",
      flags.start,
      "Unsupported MAT class; supported base classes are 1 through 15",
    )
  }
  if (bits & 0xfffffb00U) != 0U ||
    bits_at(bytes, flags.start + 4, 4, little) != 0UL {
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
    let width = encoding.width()
    let raw = if little || width == 1 {
      payload(bytes, data)
    } else {
      if data.size % width != 0 {
        fail("payload-size", data.start, "Partial character unit")
      }
      Bytes::makei(data.size, i => {
        bytes[data.start + i / width * width + width - 1 - i % width]
      })
    }
    if data.next != end {
      fail("trailing-matrix-data", data.next, "Unexpected character data")
    }
    let a : CharArray = { name, shape, encoding, data: raw, is_global, }
    ignore(validate_char(a, limits, depth > 1))
    return Character(a)
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
    values.push(
      read_node(bytes, child, little, limits, tree, budget, depth + 1),
    )
    pos = child.next
  }
  if pos != end {
    fail(
      "trailing-matrix-data", pos, "Container child count does not match dimensions/fields",
    )
  }
  if class == 1 {
    Cell({ name, shape, values, is_global, })
  } else {
    Structure({ name, shape, fields, values, class_name, is_global, })
  }
}

///|
/// Read all documented Level 5 base classes, including recursively mixed files.
pub fn read_tree(
  bytes : Bytes,
  limits? : Limits = default_limits(),
  tree_limits? : TreeLimits = default_tree_limits(),
) -> MatTree raise MatError {
  validate_limits(limits)
  validate_tree_limits(tree_limits)
  if bytes.length() > limits.max_file_bytes {
    fail("file-limit", 0, "File exceeds max_file_bytes")
  }
  if bytes.length() < 128 {
    fail("invalid-header", 0, "MAT Level 5 header needs 128 bytes")
  }
  if bytes[0:8] == b"\x89HDF\x0d\x0a\x1a\x0a" ||
    bytes[0:19] == b"MATLAB 7.3 MAT-file" {
    fail("unsupported-v7.3", 0, "HDF5 MAT v7.3 is outside MAT Level 5")
  }
  let little = if bytes[126:128] == b"IM" {
    true
  } else if bytes[126:128] == b"MI" {
    false
  } else {
    fail("invalid-header", 126, "Invalid endian marker")
    true
  }
  if bits_at(bytes, 124, 2, little) != 256UL {
    fail("unsupported-version", 124, "Expected Level 5 version 0x0100")
  }
  let subsystem = bits_at(bytes, 116, 8, little)
  if subsystem != 0UL && subsystem != 0x2020202020202020UL {
    fail(
      "unsupported-subsystem", 116, "Subsystem/object workspace metadata is unsupported",
    )
  }
  let budget : TreeBudget = { nodes: 0, elements: 0, }
  let variables = []
  let names : Map[String, Bool] = Map([])
  let mut offset = 128
  let mut expanded = 0
  while offset < bytes.length() {
    if variables.length() >= limits.max_variables {
      fail("variable-limit", offset, "Too many root variables")
    }
    let outer = tag(bytes, offset, bytes.length(), little)
    let node = if outer.kind == 14 {
      read_node(bytes, outer, little, limits, tree_limits, budget, 1)
    } else if outer.kind == 15 {
      let unpacked = inflate_zlib(
        payload(bytes, outer),
        max_bytes=limits.max_expanded_bytes - expanded,
      )
      expanded = expanded + unpacked.length()
      let inner = tag(unpacked, 0, unpacked.length(), little)
      if inner.kind != 14 || inner.next != unpacked.length() {
        fail(
          "invalid-compressed", offset, "Compressed element must contain exactly one matrix",
        )
      }
      read_node(unpacked, inner, little, limits, tree_limits, budget, 1)
    } else {
      fail("unsupported-element", offset, "Expected miMATRIX or miCOMPRESSED")
      abort("unreachable")
    }
    if names.contains(node.name()) {
      fail("duplicate-name", offset, "Duplicate root variable")
    }
    names[node.name()] = true
    variables.push(node)
    offset = outer.next
  }
  {
    description: @utf8.decode_lossy(bytes[0:116]).trim().to_owned(),
    little_endian: little,
    variables,
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
) -> Int raise MatError {
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
        let bytes = node_size(child, limits, tree, budget, depth + 1) + 8
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
      size = size + 16 + element_size(width * a.fields.length())
      if a.class_name is Some(class_name) {
        validate_name(class_name, limits)
        size = size + element_size(@utf8.encode(class_name[:]).length())
      }
      for child in a.values {
        let bytes = node_size(child, limits, tree, budget, depth + 1) + 8
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
  size
}

///|
fn encoded_node(node : MatNode) -> Bytes {
  match node {
    Numeric(a) => return encoded_matrix(a)
    Csc(a) => return encoded_sparse(a)
    _ => ()
  }
  let (class, global) = match node {
    Character(a) => (4, a.is_global)
    Cell(a) => (1, a.is_global)
    Structure(a) => (if a.class_name is Some(_) { 3 } else { 2 }, a.is_global)
    _ => abort("unreachable")
  }
  let out = []
  let flags = []
  push_bits(flags, (class + (if global { 1024 } else { 0 })).to_uint64(), 4)
  push_bits(flags, 0UL, 4)
  append_element(out, 6, Bytes::from_array(flags))
  let dims = []
  for dim in node.shape() {
    push_bits(dims, dim.to_uint64(), 4)
  }
  append_element(out, 5, Bytes::from_array(dims))
  append_element(out, 1, @utf8.encode(node.name()[:]))
  match node {
    Character(a) => append_element(out, a.encoding.tag_id(), a.data)
    Cell(a) =>
      for child in a.values {
        append_element(out, 14, encoded_node(child))
      }
    Structure(a) => {
      if a.class_name is Some(class_name) {
        append_element(out, 1, @utf8.encode(class_name[:]))
      }
      let mut width = 1
      for field in a.fields {
        let required = @utf8.encode(field[:]).length() + 1
        if required > width {
          width = required
        }
      }
      let length = []
      push_bits(length, width.to_uint64(), 4)
      append_element(out, 5, Bytes::from_array(length))
      let names = []
      for field in a.fields {
        let bytes = @utf8.encode(field[:])
        for byte in bytes {
          names.push(byte)
        }
        for i = bytes.length(); i < width; i = i + 1 {
          names.push(b'\x00')
        }
      }
      append_element(out, 1, Bytes::from_array(names))
      for child in a.values {
        append_element(out, 14, encoded_node(child))
      }
    }
    _ => ()
  }
  Bytes::from_array(out)
}

///|
/// Validate the entire tree before output allocation. Canonical output is little-endian.
pub fn write_tree(
  variables : Array[MatNode],
  compressed? : Bool = false,
  limits? : Limits = default_limits(),
  tree_limits? : TreeLimits = default_tree_limits(),
) -> Bytes raise MatError {
  validate_limits(limits)
  validate_tree_limits(tree_limits)
  if variables.length() > limits.max_variables {
    fail("variable-limit", 0, "Too many root variables")
  }
  let budget : TreeBudget = { nodes: 0, elements: 0, }
  let names : Map[String, Bool] = Map([])
  let mut size = 128
  for node in variables {
    if names.contains(node.name()) {
      fail("duplicate-name", 0, "Duplicate root variable")
    }
    names[node.name()] = true
    let bytes = node_size(node, limits, tree_limits, budget, 1) + 8
    if bytes > limits.max_file_bytes - size {
      fail("file-limit", 0, "Encoded tree exceeds byte limit")
    }
    size = size + bytes
  }
  let out = write_mat([]).to_array()
  let mut expanded = 0
  for node in variables {
    let encoded = encoded_node(node)
    if compressed {
      let matrix = []
      append_element(matrix, 14, encoded)
      if matrix.length() > limits.max_expanded_bytes - expanded {
        fail("expanded-limit", 0, "Expanded tree exceeds byte limit")
      }
      expanded = expanded + matrix.length()
      let available = limits.max_file_bytes - out.length() - 8
      if available < 6 {
        fail("file-limit", 0, "No room for compressed matrix")
      }
      append_element(
        out,
        15,
        deflate_zlib(Bytes::from_array(matrix), max_bytes=available),
      )
    } else {
      append_element(out, 14, encoded)
    }
  }
  Bytes::from_array(out)
}
