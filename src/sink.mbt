///|
/// A synchronous positional writer. Buffer is borrowed only until callback return.
pub(all) struct MatSink {
  write_from : (Int32, FixedArray[Byte], Int32, Int32) -> Int32
}

///|
pub(all) struct WriteLimits {
  max_output_bytes : Int32
  max_uncompressed_bytes : Int32
  max_metadata_bytes : Int32
  chunk_bytes : Int32
  max_elements : Int32
  max_variables : Int32
  max_dimensions : Int32
  max_name_bytes : Int32
} derive(Eq, @debug.Debug)

///|
pub fn default_write_limits() -> WriteLimits {
  {
    max_output_bytes: 1073741824,
    max_uncompressed_bytes: 1073741824,
    max_metadata_bytes: 8388608,
    chunk_bytes: 1048576,
    max_elements: 134217728,
    max_variables: 4096,
    max_dimensions: 32,
    max_name_bytes: 1024,
  }
}

///|
priv struct SinkCursor {
  buffer : FixedArray[Byte]
  consume : (Int32, FixedArray[Byte], Int32) -> Unit raise MatError
  limit : Int32
  mut offset : Int32
  mut used : Int32
  mut node : Int32
}

///|
fn sink_flush(cursor : SinkCursor) -> Unit raise MatError {
  if cursor.used > 0 {
    (cursor.consume)(cursor.offset - cursor.used, cursor.buffer, cursor.used)
    cursor.used = 0
  }
}

///|
fn sink_write_all(
  sink : MatSink,
  offset : Int32,
  buffer : FixedArray[Byte],
  start : Int32,
  count : Int32,
) -> Unit raise MatError {
  let mut done = 0
  while done < count {
    let n = (sink.write_from)(offset + done, buffer, start + done, count - done)
    if n <= 0 || n > count - done {
      fail("io-error", offset + done, "Sink returned an invalid write count")
    }
    done = done + n
  }
}

///|
fn sink_byte(cursor : SinkCursor, byte : Byte) -> Unit raise MatError {
  if cursor.offset >= cursor.limit {
    fail("file-limit", cursor.offset, "Encoded output exceeds byte limit")
  }
  cursor.buffer[cursor.used] = byte
  cursor.used = cursor.used + 1
  cursor.offset = cursor.offset + 1
  if cursor.used == cursor.buffer.length() {
    sink_flush(cursor)
  }
}

///|
fn sink_copy(
  cursor : SinkCursor,
  bytes : Bytes,
  start : Int32,
  count : Int32,
) -> Unit raise MatError {
  if count > cursor.limit - cursor.offset {
    fail("file-limit", cursor.offset, "Encoded output exceeds byte limit")
  }
  let mut done = 0
  while done < count {
    let room = cursor.buffer.length() - cursor.used
    let n = if count - done < room { count - done } else { room }
    cursor.buffer.blit_from_bytes(cursor.used, bytes, start + done, n)
    cursor.used = cursor.used + n
    cursor.offset = cursor.offset + n
    done = done + n
    if cursor.used == cursor.buffer.length() {
      sink_flush(cursor)
    }
  }
}

///|
fn sink_zeros(cursor : SinkCursor, count : Int32) -> Unit raise MatError {
  for i = 0; i < count; i = i + 1 {
    sink_byte(cursor, b'\x00')
  }
}

///|
fn sink_u32(cursor : SinkCursor, value : UInt32) -> Unit raise MatError {
  if 4 > cursor.limit - cursor.offset {
    fail("file-limit", cursor.offset, "Encoded output exceeds byte limit")
  }
  if cursor.buffer.length() - cursor.used >= 4 {
    // CSC indices and tags normally fit within a block. Update the cursor once.
    let at = cursor.used
    cursor.buffer[at] = (value & 255U).to_byte()
    cursor.buffer[at + 1] = ((value >> 8) & 255U).to_byte()
    cursor.buffer[at + 2] = ((value >> 16) & 255U).to_byte()
    cursor.buffer[at + 3] = ((value >> 24) & 255U).to_byte()
    cursor.used = cursor.used + 4
    cursor.offset = cursor.offset + 4
    if cursor.used == cursor.buffer.length() {
      sink_flush(cursor)
    }
  } else {
    for i = 0; i < 4; i = i + 1 {
      sink_byte(cursor, ((value >> (i * 8)) & 255U).to_byte())
    }
  }
}

///|
fn sink_tag(
  cursor : SinkCursor,
  kind : Int32,
  size : Int32,
) -> Unit raise MatError {
  sink_u32(cursor, kind.reinterpret_as_uint())
  sink_u32(cursor, size.reinterpret_as_uint())
}

///|
fn sink_bytes(
  cursor : SinkCursor,
  kind : Int32,
  bytes : Bytes,
) -> Unit raise MatError {
  sink_tag(cursor, kind, bytes.length())
  sink_copy(cursor, bytes, 0, bytes.length())
  if kind != 15 {
    sink_zeros(cursor, (8 - bytes.length() % 8) % 8)
  }
}

///|
fn sink_ints(cursor : SinkCursor, values : Array[Int32]) -> Unit raise MatError {
  sink_tag(cursor, 5, values.length() * 4)
  if values.length() * 4 > cursor.limit - cursor.offset {
    fail("file-limit", cursor.offset, "Encoded output exceeds byte limit")
  }
  let mut index = 0
  while index < values.length() {
    let room = (cursor.buffer.length() - cursor.used) / 4
    if room == 0 {
      sink_u32(cursor, values[index].reinterpret_as_uint())
      index = index + 1
    } else {
      let count = if values.length() - index < room {
        values.length() - index
      } else {
        room
      }
      let at = cursor.used
      for i = 0; i < count; i = i + 1 {
        let word = values[index + i].reinterpret_as_uint()
        let position = at + i * 4
        cursor.buffer[position] = word.to_byte()
        cursor.buffer[position + 1] = (word >> 8).to_byte()
        cursor.buffer[position + 2] = (word >> 16).to_byte()
        cursor.buffer[position + 3] = (word >> 24).to_byte()
      }
      cursor.used = cursor.used + count * 4
      cursor.offset = cursor.offset + count * 4
      index = index + count
      if cursor.used == cursor.buffer.length() {
        sink_flush(cursor)
      }
    }
  }
  if values.length() % 2 != 0 {
    sink_zeros(cursor, 4)
  }
}

///|
priv struct WriteMetadata {
  mut bytes : Int32
}

///|
fn write_metadata_charge(
  budget : WriteMetadata,
  amount : Int32,
  limit : Int32,
) -> Unit raise MatError {
  if amount > limit - budget.bytes {
    fail("metadata-limit", 0, "Cumulative write metadata exceeds quota")
  }
  budget.bytes = budget.bytes + amount
}

///|
fn write_metadata_node(
  node : MatNode,
  budget : WriteMetadata,
  limit : Int32,
  encoding : NameEncoding,
) -> Unit raise MatError {
  write_metadata_charge(
    budget,
    node.shape().length() * 4 + encode_name(node.name(), encoding).length(),
    limit,
  )
  match node {
    Cell(a) =>
      for child in a.values {
        write_metadata_node(child, budget, limit, encoding)
      }
    Structure(a) => {
      if a.class_name is Some(name) {
        write_metadata_charge(
          budget,
          encode_name(name, encoding).length(),
          limit,
        )
      }
      let mut width = 1
      for field in a.fields {
        let n = encode_name(field, encoding).length() + 1
        if n > width {
          width = n
        }
      }
      write_metadata_charge(budget, width * a.fields.length(), limit)
      for child in a.values {
        write_metadata_node(child, budget, limit, encoding)
      }
    }
    _ => ()
  }
}

///|
fn validate_write_limits(limits : WriteLimits) -> Limits raise MatError {
  for n in [limits.max_output_bytes, limits.max_uncompressed_bytes] {
    if n < 128 || n > 1073741824 {
      fail("invalid-limits", 0, "Invalid write byte quota")
    }
  }
  if limits.max_metadata_bytes < 0 ||
    limits.max_metadata_bytes > 1073741824 ||
    limits.chunk_bytes < 1 ||
    limits.chunk_bytes > 8388608 {
    fail("invalid-limits", 0, "Invalid write metadata or block quota")
  }
  let basic : Limits = {
    max_file_bytes: limits.max_uncompressed_bytes,
    max_expanded_bytes: limits.max_uncompressed_bytes,
    max_elements: limits.max_elements,
    max_variables: limits.max_variables,
    max_dimensions: limits.max_dimensions,
    max_name_bytes: limits.max_name_bytes,
  }
  validate_limits(basic)
  basic
}

///|
/// Preflight the complete tree, then write canonical little-endian MAT in bounded blocks.
/// An I/O error may leave partial sink contents; file adapters handle final-name atomicity.
pub fn write_tree_to(
  variables : Array[MatNode],
  sink : MatSink,
  limits~ : WriteLimits = default_write_limits(),
  tree_limits~ : TreeLimits = default_tree_limits(),
  name_encoding~ : NameEncoding = Utf8,
) -> Int32 raise MatError {
  let basic = validate_write_limits(limits)
  let (planned, _, size) = plan_tree(
    variables,
    basic,
    tree_limits,
    name_encoding~,
  )
  let metadata : WriteMetadata = { bytes: 0, }
  for node in variables {
    write_metadata_node(
      node,
      metadata,
      limits.max_metadata_bytes,
      name_encoding,
    )
  }
  if size > limits.max_output_bytes {
    fail("file-limit", 0, "Encoded tree exceeds output byte quota")
  }
  let count = if size < limits.chunk_bytes { size } else { limits.chunk_bytes }
  let cursor : SinkCursor = {
    buffer: FixedArray::make(count, b'\x00'),
    limit: limits.max_output_bytes,
    offset: 0,
    used: 0,
    node: 0,
    consume: (offset, buffer, length) => {
      sink_write_all(sink, offset, buffer, 0, length)
    },
  }
  let header = canonical_header()
  sink_copy(cursor, header, 0, header.length())
  for node in variables {
    sink_node(cursor, node, planned, name_encoding~)
  }
  guard! cursor.offset == size
  sink_flush(cursor)
  size
}

///|
pub extend WriteLimits with Eq::{equal, not_equal}

///|
pub extend WriteLimits with @debug.Debug::{to_repr}

///|
fn sink_node(
  cursor : SinkCursor,
  node : MatNode,
  planned : Array[Int32],
  name_encoding~ : NameEncoding = Utf8,
) -> Unit raise MatError {
  let body_size = planned[cursor.node]
  cursor.node = cursor.node + 1
  sink_tag(cursor, 14, body_size)
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
  sink_tag(cursor, 6, 8)
  sink_u32(
    cursor,
    (class +
    (if logical { 512 } else { 0 }) +
    (if global { 1024 } else { 0 }) +
    (if complex { 2048 } else { 0 })).reinterpret_as_uint(),
  )
  sink_u32(cursor, capacity.reinterpret_as_uint())
  sink_ints(cursor, node.shape())
  sink_bytes(cursor, 1, encode_name(node.name(), name_encoding))
  match node {
    Numeric(a) => {
      sink_bytes(cursor, a.dtype.mi_type(), a.real)
      if a.imag is Some(imag) {
        sink_bytes(cursor, a.dtype.mi_type(), imag)
      }
    }
    Csc(a) => {
      sink_ints(cursor, a.row_indices)
      sink_ints(cursor, a.col_ptrs)
      sink_bytes(cursor, a.dtype.mi_type(), a.real)
      if a.imag is Some(imag) {
        sink_bytes(cursor, a.dtype.mi_type(), imag)
      }
    }
    Character(a) => sink_bytes(cursor, a.encoding.tag_id(), a.data)
    Cell(a) =>
      for child in a.values {
        sink_node(cursor, child, planned, name_encoding~)
      }
    Structure(a) => {
      if a.class_name is Some(name) {
        sink_bytes(cursor, 1, encode_name(name, name_encoding))
      }
      let mut width = 1
      for field in a.fields {
        let count = encode_name(field, name_encoding).length() + 1
        if count > width {
          width = count
        }
      }
      sink_u32(cursor, (5 + (4 << 16)).reinterpret_as_uint())
      sink_u32(cursor, width.reinterpret_as_uint())
      let table_size = width * a.fields.length()
      sink_tag(cursor, 1, table_size)
      for field in a.fields {
        let bytes = encode_name(field, name_encoding)
        sink_copy(cursor, bytes, 0, bytes.length())
        sink_zeros(cursor, width - bytes.length())
      }
      sink_zeros(cursor, (8 - table_size % 8) % 8)
      for child in a.values {
        sink_node(cursor, child, planned, name_encoding~)
      }
    }
  }
}
