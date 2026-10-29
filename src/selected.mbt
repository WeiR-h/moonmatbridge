///|
/// Validated root metadata; offsets are intentionally not exposed or cached.
pub(all) struct MatRootInfo {
  name : String
  class_id : Int
  shape : Array[Int]
  is_global : Bool
  is_complex : Bool
  is_logical : Bool
  compressed : Bool
} derive(@debug.Debug)

///|
pub extend MatRootInfo with @debug.Debug::{to_repr}

///|
fn root_info(
  bytes : Bytes,
  outer : Element,
  little : Bool,
  limits : Limits,
  compressed : Bool,
  name_encoding? : NameEncoding = Utf8,
) -> MatRootInfo raise MatError {
  let end = outer.start + outer.size
  let flags = tag(bytes, outer.start, end, little)
  if flags.kind != 6 || flags.size != 8 {
    fail("invalid-flags", flags.start, "Expected 8-byte array flags")
  }
  let bits = bits_at(bytes, flags.start, 4, little).to_uint()
  let class_id = (bits & 255U).reinterpret_as_int()
  if class_id < 1 || class_id > 15 {
    fail(
      "unsupported-class",
      flags.start,
      "Supported base classes are 1 through 15",
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
  let name = tag(bytes, dims.next, end, little)
  let name = tree_text(bytes, name, limits, false, name_encoding~)
  {
    name,
    class_id,
    shape,
    is_global: (bits & 1024U) != 0U,
    is_complex: (bits & 2048U) != 0U,
    is_logical: (bits & 512U) != 0U,
    compressed,
  }
}

///|
fn scan_tree(
  bytes : Bytes,
  selection : Array[String]?,
  collect_roots : Bool,
  limits : Limits,
  tree_limits : TreeLimits,
  name_encoding? : NameEncoding = Utf8,
) -> (MatTree, Array[MatRootInfo]) raise MatError {
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
  let wanted : Map[String, Bool] = Map([])
  if selection is Some(names) {
    for name in names {
      wanted[name] = true
    }
  }
  let budget : TreeBudget = {
    nodes: 0,
    elements: 0,
    metadata: 0,
    metadata_limit: 0,
  }
  let variables = []
  let roots = []
  let kept : Map[String, MatNode] = Map([])
  let seen : Map[String, Bool] = Map([])
  let mut offset = 128
  let mut expanded = 0
  let mut root_count = 0
  while offset < bytes.length() {
    if root_count >= limits.max_variables {
      fail("variable-limit", offset, "Too many root variables")
    }
    let outer = tag(bytes, offset, bytes.length(), little)
    let (source, inner, compressed) = if outer.kind == 14 {
      (bytes, outer, false)
    } else if outer.kind == 15 {
      let unpacked = inflate_window(
        bytes,
        outer.start,
        outer.size,
        limits.max_expanded_bytes - expanded,
        Some(little),
      )
      expanded = expanded + unpacked.length()
      let inner = tag(unpacked, 0, unpacked.length(), little)
      if inner.kind != 14 || inner.next != unpacked.length() {
        fail(
          "invalid-compressed", offset, "Compressed element must contain exactly one matrix",
        )
      }
      (unpacked, inner, true)
    } else {
      fail("unsupported-element", offset, "Expected miMATRIX or miCOMPRESSED")
      abort("unreachable")
    }
    let info = root_info(
      source,
      inner,
      little,
      limits,
      compressed,
      name_encoding~,
    )
    let keep = selection is None || wanted.contains(info.name)
    let value = visit_node(
      source,
      inner,
      little,
      limits,
      tree_limits,
      budget,
      1,
      keep,
      name_encoding~,
    )
    if seen.contains(info.name) {
      fail("duplicate-name", offset, "Duplicate root variable")
    }
    seen[info.name] = true
    if value is Some(node) {
      variables.push(node)
      if selection is Some(_) {
        kept[info.name] = node
      }
    }
    if collect_roots {
      roots.push(info)
    }
    root_count = root_count + 1
    offset = outer.next
  }
  let ordered = if selection is Some(names) {
    let result = []
    let selected : Map[String, Bool] = Map([])
    for name in names {
      if selected.contains(name) {
        fail("duplicate-name", 0, "Repeated selection: " + name)
      }
      selected[name] = true
      match kept.get(name) {
        Some(node) => result.push(node)
        None => fail("missing-variable", 0, "No variable named: " + name)
      }
    }
    result
  } else {
    variables
  }
  (
    {
      description: @utf8.decode_lossy(bytes[0:116]).trim().to_owned(),
      little_endian: little,
      variables: ordered,
    },
    roots,
  )
}

///|
/// Validate every variable while constructing only the requested data trees.
pub fn read_selected(
  bytes : Bytes,
  names : Array[String],
  limits? : Limits = default_limits(),
  tree_limits? : TreeLimits = default_tree_limits(),
  name_encoding? : NameEncoding = Utf8,
) -> MatTree raise MatError {
  let (file, _) = scan_tree(
    bytes,
    Some(names),
    false,
    limits,
    tree_limits,
    name_encoding~,
  )
  file
}

///|
/// Full validation with no persistent data trees; compressed roots are decoded.
pub fn inspect_roots(
  bytes : Bytes,
  limits? : Limits = default_limits(),
  tree_limits? : TreeLimits = default_tree_limits(),
  name_encoding? : NameEncoding = Utf8,
) -> Array[MatRootInfo] raise MatError {
  let (_, roots) = scan_tree(
    bytes,
    Some([]),
    true,
    limits,
    tree_limits,
    name_encoding~,
  )
  roots
}

///|
pub fn read_tree(
  bytes : Bytes,
  limits? : Limits = default_limits(),
  tree_limits? : TreeLimits = default_tree_limits(),
  name_encoding? : NameEncoding = Utf8,
) -> MatTree raise MatError {
  let (file, _) = scan_tree(
    bytes,
    None,
    false,
    limits,
    tree_limits,
    name_encoding~,
  )
  file
}
