///|
priv struct WriteCursor {
  mut offset : Int32
  mut node : Int32
}

///|
/// Ownership transfer: buffers are freshly allocated privately, never escape to
/// callers while mutable, and are never modified after this final conversion.
fn finish_owned_buffer(buffer : FixedArray[Byte]) -> Bytes {
  buffer.unsafe_reinterpret_as_bytes()
}

///|
fn fixed_u32(
  out : FixedArray[Byte],
  cursor : WriteCursor,
  value : UInt64,
) -> Unit {
  for i = 0; i < 4; i = i + 1 {
    out[cursor.offset + i] = ((value >> (i * 8)) & 255UL).to_byte()
  }
  cursor.offset = cursor.offset + 4
}

///|
fn fixed_tag(
  out : FixedArray[Byte],
  cursor : WriteCursor,
  kind : Int32,
  size : Int32,
) -> Unit {
  fixed_u32(out, cursor, kind.to_uint64())
  fixed_u32(out, cursor, size.to_uint64())
}

///|
fn fixed_bytes(
  out : FixedArray[Byte],
  cursor : WriteCursor,
  kind : Int32,
  bytes : Bytes,
) -> Unit {
  fixed_tag(out, cursor, kind, bytes.length())
  out.blit_from_bytes(cursor.offset, bytes, 0, bytes.length())
  cursor.offset = cursor.offset +
    bytes.length() +
    (if kind == 15 { 0 } else { (8 - bytes.length() % 8) % 8 })
}

///|
fn fixed_ints(
  out : FixedArray[Byte],
  cursor : WriteCursor,
  values : Array[Int32],
) -> Unit {
  fixed_tag(out, cursor, 5, values.length() * 4)
  let start = cursor.offset
  for i = 0; i < values.length(); i = i + 1 {
    let value = values[i].reinterpret_as_uint()
    let position = start + i * 4
    out[position] = value.to_byte()
    out[position + 1] = (value >> 8).to_byte()
    out[position + 2] = (value >> 16).to_byte()
    out[position + 3] = (value >> 24).to_byte()
  }
  cursor.offset = start +
    values.length() * 4 +
    (if values.length() % 2 == 0 { 0 } else { 4 })
}

///|
fn canonical_header() -> Bytes {
  let out = FixedArray::make(128, b' ')
  let text = @utf8.encode(
    ("MATLAB 5.0 MAT-file, Created by MoonMatBridge v" +
    version() +
    " (MoonBit)")[:],
  )
  out.blit_from_bytes(0, text, 0, text.length())
  for i = 116; i < 126; i = i + 1 {
    out[i] = b'\x00'
  }
  out[125] = b'\x01'
  out[126] = b'I'
  out[127] = b'M'
  finish_owned_buffer(out)
}

///|
fn fixed_node(
  out : FixedArray[Byte],
  cursor : WriteCursor,
  node : MatNode,
  planned : Array[Int32],
  name_encoding~ : NameEncoding = Utf8,
) -> Unit raise MatError {
  let body_size = planned[cursor.node]
  cursor.node = cursor.node + 1
  fixed_tag(out, cursor, 14, body_size)
  let (class, logical, complex, global, capacity) = match node {
    Numeric(a) =>
      (
        a.dtype.mat_class(),
        a.dtype == Logical,
        a.imag is Some(_),
        a.is_global,
        0,
      )
    Csc(a) => (5, a.dtype == Logical, a.imag is Some(_), a.is_global, a.nzmax)
    Character(a) => (4, false, false, a.is_global, 0)
    Cell(a) => (1, false, false, a.is_global, 0)
    Structure(a) =>
      (
        if a.class_name is Some(_) {
          3
        } else {
          2
        },
        false,
        false,
        a.is_global,
        0,
      )
  }
  fixed_tag(out, cursor, 6, 8)
  fixed_u32(
    out,
    cursor,
    (class +
    (if logical { 512 } else { 0 }) +
    (if global { 1024 } else { 0 }) +
    (if complex { 2048 } else { 0 })).to_uint64(),
  )
  fixed_u32(out, cursor, capacity.to_uint64())
  fixed_ints(out, cursor, node.shape())
  fixed_bytes(out, cursor, 1, encode_name(node.name(), name_encoding))
  match node {
    Numeric(a) => {
      fixed_bytes(out, cursor, a.dtype.mi_type(), a.real)
      if a.imag is Some(imag) {
        fixed_bytes(out, cursor, a.dtype.mi_type(), imag)
      }
    }
    Csc(a) => {
      fixed_ints(out, cursor, a.row_indices)
      fixed_ints(out, cursor, a.col_ptrs)
      fixed_bytes(out, cursor, a.dtype.mi_type(), a.real)
      if a.imag is Some(imag) {
        fixed_bytes(out, cursor, a.dtype.mi_type(), imag)
      }
    }
    Character(a) => fixed_bytes(out, cursor, a.encoding.tag_id(), a.data)
    Cell(a) =>
      for child in a.values {
        fixed_node(out, cursor, child, planned, name_encoding~)
      }
    Structure(a) => {
      if a.class_name is Some(name) {
        fixed_bytes(out, cursor, 1, encode_name(name, name_encoding))
      }
      let mut width = 1
      for field in a.fields {
        let count = encode_name(field, name_encoding).length() + 1
        if count > width {
          width = count
        }
      }
      fixed_u32(out, cursor, (5 + (4 << 16)).to_uint64())
      fixed_u32(out, cursor, width.to_uint64())
      let table_size = width * a.fields.length()
      fixed_tag(out, cursor, 1, table_size)
      for field in a.fields {
        let bytes = encode_name(field, name_encoding)
        out.blit_from_bytes(cursor.offset, bytes, 0, bytes.length())
        cursor.offset = cursor.offset + width
      }
      cursor.offset = cursor.offset + (8 - table_size % 8) % 8
      for child in a.values {
        fixed_node(out, cursor, child, planned, name_encoding~)
      }
    }
  }
}

///|
fn plan_tree(
  variables : Array[MatNode],
  limits : Limits,
  tree_limits : TreeLimits,
  name_encoding~ : NameEncoding = Utf8,
) -> (Array[Int32], Array[Int32], Int32) raise MatError {
  validate_limits(limits)
  validate_tree_limits(tree_limits)
  if variables.length() > limits.max_variables {
    fail("variable-limit", 0, "Too many root variables")
  }
  let budget : TreeBudget = {
    nodes: 0,
    elements: 0,
    metadata: 0,
    metadata_limit: 0,
  }
  let names : Map[String, Bool] = Map([])
  let planned = []
  let roots = []
  let mut size = 128
  for node in variables {
    if names.contains(node.name()) {
      fail("duplicate-name", 0, "Duplicate root variable")
    }
    names[node.name()] = true
    roots.push(planned.length())
    let length = node_size(
        node,
        limits,
        tree_limits,
        budget,
        1,
        planned,
        name_encoding~,
      ) +
      8
    if length > limits.max_file_bytes - size {
      fail("file-limit", 0, "Encoded tree exceeds byte limit")
    }
    size = size + length
  }
  (planned, roots, size)
}

///|
/// Validate recursive data and cumulative budgets without constructing MAT bytes.
pub fn validate_tree(
  variables : Array[MatNode],
  limits~ : Limits = default_limits(),
  tree_limits~ : TreeLimits = default_tree_limits(),
  name_encoding~ : NameEncoding = Utf8,
) -> Unit raise MatError {
  ignore(plan_tree(variables, limits, tree_limits, name_encoding~))
}

///|
/// Preflight all nodes, then write directly to a privately owned fixed buffer.
pub fn write_tree(
  variables : Array[MatNode],
  compressed~ : Bool = false,
  limits~ : Limits = default_limits(),
  tree_limits~ : TreeLimits = default_tree_limits(),
  name_encoding~ : NameEncoding = Utf8,
) -> Bytes raise MatError {
  let (planned, roots, size) = plan_tree(
    variables,
    limits,
    tree_limits,
    name_encoding~,
  )
  let header = canonical_header()
  if !compressed {
    let out = FixedArray::make(size, b'\x00')
    out.blit_from_bytes(0, header, 0, 128)
    let cursor : WriteCursor = { offset: 128, node: 0, }
    for node in variables {
      fixed_node(out, cursor, node, planned, name_encoding~)
    }
    guard! cursor.offset == size
    return finish_owned_buffer(out)
  }
  let chunks = []
  let mut total = 128
  let mut expanded = 0
  for i = 0; i < variables.length(); i = i + 1 {
    let length = planned[roots[i]] + 8
    if length > limits.max_expanded_bytes - expanded {
      fail("expanded-limit", 0, "Expanded tree exceeds byte limit")
    }
    expanded = expanded + length
    let raw = FixedArray::make(length, b'\x00')
    let cursor : WriteCursor = { offset: 0, node: roots[i], }
    fixed_node(raw, cursor, variables[i], planned, name_encoding~)
    guard! cursor.offset == length
    let available = limits.max_file_bytes - total - 8
    if available < 6 {
      fail("file-limit", 0, "No room for compressed matrix")
    }
    let chunk = deflate_zlib(finish_owned_buffer(raw), max_bytes=available)
    total = total + chunk.length() + 8
    chunks.push(chunk)
  }
  let out = FixedArray::make(total, b'\x00')
  out.blit_from_bytes(0, header, 0, 128)
  let cursor : WriteCursor = { offset: 128, node: 0, }
  for chunk in chunks {
    fixed_bytes(out, cursor, 15, chunk)
  }
  guard! cursor.offset == total
  finish_owned_buffer(out)
}
