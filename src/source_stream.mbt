///|
priv struct SourceCursor {
  source : MatSource
  buffer : FixedArray[Byte]
  mut position : Int
  mut start : Int
  mut available : Int
}

///|
fn SourceCursor::byte(self : SourceCursor) -> Byte raise MatError {
  if self.position < self.start || self.position >= self.start + self.available {
    if self.position >= self.source.size {
      fail("truncated-data", self.position, "Unexpected source end")
    }
    self.start = self.position
    self.available = if self.source.size - self.position < self.buffer.length() {
      self.source.size - self.position
    } else {
      self.buffer.length()
    }
    source_fill(
      self.source,
      self.position,
      self.buffer,
      0,
      self.available,
      self.buffer.length(),
    )
  }
  let value = self.buffer[self.position - self.start]
  self.position = self.position + 1
  value
}

///|
fn SourceCursor::owned(
  self : SourceCursor,
  count : Int,
) -> Bytes raise MatError {
  if count < 0 || count > self.source.size - self.position {
    fail("truncated-data", self.position, "Payload exceeds source")
  }
  let out = FixedArray::make(count, b'\x00')
  let mut done = 0
  while done < count {
    out[done] = self.byte()
    done = done + 1
    let available = self.start + self.available - self.position
    let n = if available < count - done { available } else { count - done }
    self.buffer.blit_to(
      out,
      len=n,
      src_offset=self.position - self.start,
      dst_offset=done,
    )
    self.position = self.position + n
    done = done + n
  }
  finish_owned_buffer(out)
}

///|
fn SourceCursor::skip(self : SourceCursor, count : Int) -> Unit raise MatError {
  if count < 0 || count > self.source.size - self.position {
    fail("truncated-data", self.position, "Payload exceeds source")
  }
  let end = self.position + count
  while self.position < end {
    ignore(self.byte())
    let available = self.start + self.available - self.position
    self.position = self.position +
      (if available > end - self.position {
        end - self.position
      } else {
        available
      })
  }
}

///|
priv struct SourceTag {
  kind : Int
  size : Int
  start : Int
  next : Int
  inline_data : Bytes?
}

///|
fn SourceCursor::tag(
  self : SourceCursor,
  end : Int,
  little : Bool,
) -> SourceTag raise MatError {
  let offset = self.position
  if end - offset < 8 {
    fail("truncated-tag", offset, "Element tag needs eight bytes")
  }
  let raw = self.owned(8)
  let word = bits_at(raw, 0, 4, little).to_uint()
  let small = (word >> 16).reinterpret_as_int()
  if small != 0 {
    let kind = (word & 65535U).reinterpret_as_int()
    if small > 4 || kind == 0 || kind == 14 || kind == 15 {
      fail("invalid-small-tag", offset, "Invalid inline element")
    }
    return {
      kind,
      size: small,
      start: offset + 4,
      next: offset + 8,
      inline_data: Some(raw[4:4 + small].to_owned()),
    }
  }
  let kind = word.reinterpret_as_int()
  let size = bits_at(raw, 4, 4, little)
  if size > (end - offset - 8).to_uint64() {
    fail("truncated-data", offset, "Element exceeds enclosing matrix")
  }
  let n = size.to_int()
  let padding = if kind == 15 { 0 } else { (8 - n % 8) % 8 }
  if padding > end - offset - 8 - n {
    fail("truncated-padding", offset, "Missing element padding")
  }
  {
    kind,
    size: n,
    start: self.position,
    next: self.position + n + padding,
    inline_data: None,
  }
}

///|
fn SourceCursor::payload(
  self : SourceCursor,
  tag : SourceTag,
) -> Bytes raise MatError {
  let out = match tag.inline_data {
    Some(b) => b
    None => self.owned(tag.size)
  }
  self.finish(tag)
  out
}

///|
fn SourceCursor::finish(
  self : SourceCursor,
  tag : SourceTag,
) -> Unit raise MatError {
  self.skip(tag.next - self.position)
}

///|
priv struct SourceScan {
  limits : SourceLimits
  basic : Limits
  tree : TreeLimits
  budget : TreeBudget
  wanted : Map[String, Bool]?
  mut result_size : Int
  mut expanded : Int
}

///|
fn SourceScan::metadata(self : SourceScan, count : Int) -> Unit raise MatError {
  if count > self.limits.max_metadata_bytes - self.budget.metadata {
    fail("metadata-limit", 0, "Cumulative source metadata exceeds quota")
  }
  self.budget.metadata = self.budget.metadata + count
}

///|
fn SourceScan::result(
  self : SourceScan,
  count : Int,
  keep : Bool,
) -> Unit raise MatError {
  if !keep {
    return
  }
  if count < 0 || count > self.limits.max_result_bytes - self.result_size {
    fail("result-limit", 0, "Selected normalized MAT exceeds quota")
  }
  self.result_size = self.result_size + count
}

///|
fn source_text_value(
  raw : Bytes,
  limits : Limits,
  empty : Bool,
) -> String raise MatError {
  tree_text(
    raw,
    { kind: 1, start: 0, size: raw.length(), next: raw.length(), },
    limits,
    empty,
  )
}

///|
fn source_plane(
  cursor : SourceCursor,
  tag : SourceTag,
  count : Int,
  dtype : DType,
  little : Bool,
  keep : Bool,
) -> Bytes raise MatError {
  let storage = from_mi_type(tag.kind, tag.start)
  if count > 1073741824 / storage.width() || tag.size != count * storage.width() {
    fail("payload-size", tag.start, "Numeric plane size differs from shape")
  }
  if !keep && (storage == dtype || dtype == Logical) {
    cursor.finish(tag)
    return b""
  }
  if storage == dtype && little {
    let bytes = cursor.payload(tag)
    return bytes
  }
  let out = FixedArray::make(
    if keep {
      count * dtype.width()
    } else {
      0
    },
    b'\x00',
  )
  let mut done = 0
  let block_elements = if cursor.buffer.length() / storage.width() > 0 {
    cursor.buffer.length() / storage.width()
  } else {
    1
  }
  while done < count {
    let n = if count - done > block_elements {
      block_elements
    } else {
      count - done
    }
    let bytes = match tag.inline_data {
      Some(b) =>
        b[done * storage.width():(done + n) * storage.width()].to_owned()
      None => cursor.owned(n * storage.width())
    }
    let converted = numeric_payload(
      bytes,
      { kind: tag.kind, start: 0, size: bytes.length(), next: bytes.length(), },
      dtype,
      n,
      little,
      keep~,
    )
    if keep {
      out.blit_from_bytes(
        done * dtype.width(),
        converted,
        0,
        converted.length(),
      )
    }
    done = done + n
  }
  cursor.finish(tag)
  finish_owned_buffer(out)
}

///|
fn source_indices(
  cursor : SourceCursor,
  tag : SourceTag,
  keep : Bool,
  row_bound : Int,
  slots : Int,
  pointers : Bool,
  little : Bool,
) -> (Array[Int], Int) raise MatError {
  let count = tag.size / 4
  let out = if keep { Array::make(count, 0) } else { [] }
  let mut first_bad = -1
  let mut last = 0
  for i = 0; i < count; i = i + 1 {
    let data = match tag.inline_data {
      Some(b) => b[i * 4:i * 4 + 4].to_owned()
      None => cursor.owned(4)
    }
    let value = csc_index_at(data, 0, little)
    if pointers {
      if (i == 0 && value != 0) || value < last || value > slots {
        fail("invalid-sparse", tag.start + i * 4, "Invalid CSC pointer")
      }
      last = value
    } else if first_bad < 0 && (value < 0 || value >= row_bound) {
      first_bad = i
    }
    if keep {
      out[i] = value
    }
  }
  cursor.finish(tag)
  (out, if pointers { last } else { first_bad })
}

///|
fn source_character(
  cursor : SourceCursor,
  tag : SourceTag,
  encoding : CharEncoding,
  count : Int,
  little : Bool,
  keep : Bool,
) -> Bytes raise MatError {
  if keep {
    let bytes = cursor.payload(tag)
    validate_char_units(bytes[:], encoding, count, little)
    let width = encoding.width()
    return if little || width == 1 {
      bytes
    } else {
      Bytes::makei(bytes.length(), i => {
        bytes[i / width * width + width - 1 - i % width]
      })
    }
  }
  if encoding != Utf8 {
    if count > 1073741824 / encoding.width() ||
      tag.size != count * encoding.width() {
      fail("payload-size", tag.start, "Character unit count differs from shape")
    }
    if encoding == Utf32 {
      for i = 0; i < count; i = i + 1 {
        let bytes = match tag.inline_data {
          Some(b) => b[i * 4:i * 4 + 4].to_owned()
          None => cursor.owned(4)
        }
        let cp = bits_at(bytes, 0, 4, little)
        if cp > 1114111UL || (cp >= 55296UL && cp <= 57343UL) {
          fail("invalid-char", tag.start + i * 4, "Invalid UTF32 scalar")
        }
      }
    }
    cursor.finish(tag)
    return b""
  }
  let mut remaining = 0
  let mut cp = 0
  let mut minimum = 0
  let mut scalars = 0
  for i = 0; i < tag.size; i = i + 1 {
    let byte = match tag.inline_data {
      Some(b) => b[i].to_int()
      None => cursor.byte().to_int()
    }
    if remaining == 0 {
      if byte < 128 {
        scalars = scalars + 1
      } else if byte >= 194 && byte <= 223 {
        remaining = 1
        cp = byte & 31
        minimum = 128
      } else if byte >= 224 && byte <= 239 {
        remaining = 2
        cp = byte & 15
        minimum = 2048
      } else if byte >= 240 && byte <= 244 {
        remaining = 3
        cp = byte & 7
        minimum = 65536
      } else {
        fail("invalid-char", tag.start + i, "Invalid UTF8 leading byte")
      }
    } else {
      if (byte & 192) != 128 {
        fail("invalid-char", tag.start + i, "Invalid UTF8 continuation")
      }
      cp = (cp << 6) | (byte & 63)
      remaining = remaining - 1
      if remaining == 0 {
        if cp < minimum || cp > 1114111 || (cp >= 55296 && cp <= 57343) {
          fail("invalid-char", tag.start + i, "Invalid UTF8 scalar")
        }
        scalars = scalars + 1
      }
    }
  }
  if remaining != 0 {
    fail("invalid-char", tag.start, "Truncated UTF8 scalar")
  }
  if scalars != count {
    fail("payload-size", tag.start, "UTF8 scalar count differs from dimensions")
  }
  cursor.finish(tag)
  b""
}

///|
fn source_stream_node(
  cursor : SourceCursor,
  outer : SourceTag,
  little : Bool,
  state : SourceScan,
  depth : Int,
  keep_parent : Bool,
) -> (MatNode?, MatRootInfo) raise MatError {
  charge_node(state.budget, depth, state.tree)
  if outer.kind != 14 {
    fail("invalid-child", outer.start, "Expected matrix child")
  }
  if outer.size == 0 && depth > 1 {
    state.result(56, keep_parent)
    return (
      if keep_parent {
        Some(
          Numeric({
            name: "",
            dtype: Float64,
            shape: [0, 0],
            real: b"",
            imag: None,
            is_global: false,
          }),
        )
      } else {
        None
      },
      {
        name: "",
        class_id: 6,
        shape: [0, 0],
        is_global: false,
        is_complex: false,
        is_logical: false,
        compressed: false,
      },
    )
  }
  let end = outer.start + outer.size
  let flags = cursor.tag(end, little)
  if flags.kind != 6 || flags.size != 8 {
    fail("invalid-flags", flags.start, "Expected array flags")
  }
  let flags_data = cursor.payload(flags)
  let bits = bits_at(flags_data, 0, 4, little).to_uint()
  let reserved = bits_at(flags_data, 4, 4, little)
  let class = (bits & 255U).reinterpret_as_int()
  if class < 1 || class > 15 {
    fail("unsupported-class", flags.start, "Unsupported base class")
  }
  let allowed = if class <= 4 { 0xfffffb00U } else { 0xfffff100U }
  if (bits & allowed) != 0U || (class != 5 && reserved > 1UL) {
    fail("unsupported-flags", flags.start, "Unknown flags or reserved metadata")
  }
  let complex = (bits & 2048U) != 0U
  let logical = (bits & 512U) != 0U
  let dtype = if logical {
    Logical
  } else if class == 5 {
    Float64
  } else if class >= 6 {
    from_mat_class(class, flags.start)
  } else {
    Float64
  }
  if complex && dtype != Float64 && dtype != Float32 {
    fail(
      "unsupported-complex",
      flags.start,
      "Complex storage needs floating data",
    )
  }
  let dims = cursor.tag(end, little)
  if dims.kind != 5 ||
    dims.size < 8 ||
    dims.size % 4 != 0 ||
    dims.size / 4 > state.basic.max_dimensions {
    fail("invalid-shape", dims.start, "Invalid dimension vector")
  }
  state.metadata(dims.size)
  let data = cursor.payload(dims)
  let shape = Array::makei(data.length() / 4, i => {
    csc_index_at(data, i * 4, little)
  })
  if class == 5 &&
    (
      shape.length() != 2 ||
      shape[0] < 0 ||
      shape[1] < 0 ||
      shape[1] >= state.basic.max_elements
    ) {
    fail("invalid-shape", dims.start, "Invalid CSC shape")
  }
  let count = if class == 5 {
    0
  } else {
    element_count(shape, state.basic, dims.start)
  }
  if class != 5 {
    charge_elements(state.budget, count, state.basic)
  }
  let name_tag = cursor.tag(end, little)
  if name_tag.kind != 1 || name_tag.size > state.basic.max_name_bytes {
    fail("invalid-name", name_tag.start, "Invalid matrix name")
  }
  state.metadata(name_tag.size)
  let name = source_text_value(cursor.payload(name_tag), state.basic, depth > 1)
  let keep = if depth == 1 {
    match state.wanted {
      None => true
      Some(w) => w.contains(name)
    }
  } else {
    keep_parent
  }
  let info : MatRootInfo = {
    name,
    class_id: class,
    shape: shape.copy(),
    is_global: (bits & 1024U) != 0U,
    is_complex: complex,
    is_logical: logical,
    compressed: false,
  }
  state.result(
    8 + 16 + element_size(dims.size) + element_size(name_tag.size),
    keep,
  )
  let value : MatNode? = if class >= 6 {
    let real_tag = cursor.tag(end, little)
    state.result(element_size(count * dtype.width()), keep)
    let real = source_plane(cursor, real_tag, count, dtype, little, keep)
    let imag = if complex {
      let tag = cursor.tag(end, little)
      state.result(element_size(count * dtype.width()), keep)
      Some(source_plane(cursor, tag, count, dtype, little, keep))
    } else {
      None
    }
    if keep {
      Some(
        Numeric({ name, shape, dtype, real, imag, is_global: info.is_global, }),
      )
    } else {
      None
    }
  } else if class == 5 {
    let ir = cursor.tag(end, little)
    if ir.kind != 5 ||
      ir.size % 4 != 0 ||
      ir.size / 4 > state.basic.max_elements {
      fail("invalid-sparse", ir.start, "Invalid row vector")
    }
    let slots = ir.size / 4
    charge_elements(state.budget, slots, state.basic)
    if reserved < slots.to_uint64() ||
      reserved > state.basic.max_elements.to_uint64() {
      fail("element-limit", flags.start, "Invalid CSC capacity")
    }
    state.result(element_size(ir.size), keep)
    let (rows, bad) = source_indices(
      cursor,
      ir,
      keep,
      shape[0],
      slots,
      false,
      little,
    )
    let jc = cursor.tag(end, little)
    if jc.kind != 5 || jc.size != (shape[1] + 1) * 4 {
      fail("invalid-sparse", jc.start, "Invalid column pointers")
    }
    state.result(element_size(jc.size), keep)
    let (cols, active) = source_indices(
      cursor, jc, keep, 0, slots, true, little,
    )
    if bad >= 0 && bad < active {
      fail("invalid-sparse", ir.start + bad * 4, "Active row outside shape")
    }
    let tag = cursor.tag(end, little)
    if dtype == Float64 && tag.kind != 9 {
      fail(
        "unsupported-sparse-dtype",
        tag.start,
        "Sparse numeric plane must be double",
      )
    }
    state.result(element_size(slots * dtype.width()), keep)
    let real = source_plane(cursor, tag, slots, dtype, little, keep)
    let imag = if complex {
      let tag = cursor.tag(end, little)
      if tag.kind != 9 {
        fail(
          "unsupported-sparse-dtype",
          tag.start,
          "Sparse imaginary plane must be double",
        )
      }
      state.result(element_size(slots * dtype.width()), keep)
      Some(source_plane(cursor, tag, slots, dtype, little, keep))
    } else {
      None
    }
    if keep {
      Some(
        Csc({
          name,
          shape,
          dtype,
          row_indices: rows,
          col_ptrs: cols,
          real,
          imag,
          nzmax: reserved.to_int(),
          is_global: info.is_global,
        }),
      )
    } else {
      None
    }
  } else if class == 4 {
    let tag = cursor.tag(end, little)
    let encoding : CharEncoding = match tag.kind {
      1 => Int8Text
      2 => UInt8Text
      4 => UInt16Text
      16 => Utf8
      17 => Utf16
      18 => Utf32
      _ => {
        fail(
          "unsupported-char-encoding",
          tag.start,
          "Unknown character encoding",
        )
        Utf8
      }
    }
    state.result(element_size(tag.size), keep)
    let raw = source_character(cursor, tag, encoding, count, little, keep)
    if keep {
      Some(
        Character({
          name,
          shape,
          encoding,
          data: raw,
          is_global: info.is_global,
        }),
      )
    } else {
      None
    }
  } else {
    let class_name = if class == 3 {
      let tag = cursor.tag(end, little)
      if tag.kind != 1 || tag.size > state.basic.max_name_bytes {
        fail("invalid-name", tag.start, "Invalid legacy class name")
      }
      state.metadata(tag.size)
      state.result(element_size(tag.size), keep)
      Some(source_text_value(cursor.payload(tag), state.basic, false))
    } else {
      None
    }
    let fields : Array[String] = []
    if class == 2 || class == 3 {
      let tag = cursor.tag(end, little)
      if tag.kind != 5 || tag.size != 4 {
        fail("invalid-fields", tag.start, "Expected field width")
      }
      let data = cursor.payload(tag)
      let width = bits_at(data, 0, 4, little)
      if width < 1UL || width > (state.basic.max_name_bytes + 1).to_uint64() {
        fail("invalid-fields", tag.start, "Invalid field width")
      }
      let width = width.to_int()
      let table = cursor.tag(end, little)
      if table.kind != 1 ||
        table.size % width != 0 ||
        table.size / width > state.tree.max_fields {
        fail("invalid-fields", table.start, "Invalid field table")
      }
      state.metadata(table.size)
      let data = cursor.payload(table)
      let seen : Map[String, Bool] = Map([])
      let mut canonical_width = 1
      for i = 0; i < data.length() / width; i = i + 1 {
        let start = i * width
        let mut length = 0
        while length < width && data[start + length] != b'\x00' {
          length = length + 1
        }
        if length == width {
          fail(
            "invalid-fields",
            table.start + start,
            "Missing field terminator",
          )
        }
        for j = length; j < width; j = j + 1 {
          if data[start + j] != b'\x00' {
            fail(
              "invalid-fields",
              table.start + start + j,
              "Nonzero field padding",
            )
          }
        }
        let field = source_text_value(
          data[start:start + length].to_owned(),
          state.basic,
          false,
        )
        if seen.contains(field) {
          fail("duplicate-field", table.start + start, "Duplicate field")
        }
        seen[field] = true
        fields.push(field)
        if length + 1 > canonical_width {
          canonical_width = length + 1
        }
      }
      state.result(8 + element_size(canonical_width * fields.length()), keep)
    }
    let multiplier = if class == 1 { 1 } else { fields.length() }
    if multiplier > 0 &&
      count > (state.tree.max_nodes - state.budget.nodes) / multiplier {
      fail("node-limit", cursor.position, "Container children exceed quota")
    }
    let values = []
    for _i = 0; _i < count * multiplier; _i = _i + 1 {
      let tag = cursor.tag(end, little)
      let (child, _) = source_stream_node(
        cursor,
        tag,
        little,
        state,
        depth + 1,
        keep,
      )
      if child is Some(n) {
        values.push(n)
      }
    }
    if keep {
      if class == 1 {
        Some(Cell({ name, shape, values, is_global: info.is_global, }))
      } else {
        Some(
          Structure({
            name,
            shape,
            values,
            fields,
            class_name,
            is_global: info.is_global,
          }),
        )
      }
    } else {
      None
    }
  }
  if cursor.position != end {
    fail(
      "trailing-matrix-data",
      cursor.position,
      "Unexpected trailing matrix content",
    )
  }
  cursor.finish(outer)
  (value, info)
}

///|
fn scan_source_stream(
  source : MatSource,
  selection : Array[String]?,
  collect : Bool,
  limits : SourceLimits,
  tree : TreeLimits,
) -> (MatTree, Array[MatRootInfo]) raise MatError {
  let basic = source_limits(limits)
  validate_tree_limits(tree)
  if source.size < 128 {
    fail("invalid-header", 0, "MAT header needs 128 bytes")
  }
  if source.size > limits.max_source_bytes {
    fail("file-limit", 0, "Source exceeds input quota")
  }
  let cursor : SourceCursor = {
    source,
    buffer: FixedArray::make(limits.chunk_bytes, b'\x00'),
    position: 0,
    start: 0,
    available: 0,
  }
  let header = cursor.owned(128)
  let file = read_tree(header, limits=basic, tree_limits=tree)
  let little = file.little_endian
  let wanted : Map[String, Bool]? = selection.map(names => {
    let map : Map[String, Bool] = Map([])
    for name in names {
      map[name] = true
    }
    map
  })
  let state : SourceScan = {
    limits,
    basic,
    tree,
    wanted,
    result_size: 128,
    expanded: 0,
    budget: {
      nodes: 0,
      elements: 0,
      metadata: 0,
      metadata_limit: limits.max_metadata_bytes,
    },
  }
  let variables = []
  let roots = []
  let seen : Map[String, Bool] = Map([])
  let kept : Map[String, MatNode] = Map([])
  let mut count = 0
  while cursor.position < source.size {
    if count >= limits.max_variables {
      fail("variable-limit", cursor.position, "Too many roots")
    }
    let outer = cursor.tag(source.size, little)
    let (node, root) = if outer.kind == 14 {
      source_stream_node(cursor, outer, little, state, 1, false)
    } else if outer.kind == 15 {
      if outer.size > limits.max_buffered_root_bytes {
        fail(
          "source-buffer-limit",
          outer.start,
          "Compressed root exceeds staging quota",
        )
      }
      let raw = cursor.payload(outer)
      let maximum = if limits.max_expanded_bytes - state.expanded <
        limits.max_buffered_root_bytes {
        limits.max_expanded_bytes - state.expanded
      } else {
        limits.max_buffered_root_bytes
      }
      let unpacked = inflate_zlib(raw, max_bytes=maximum)
      state.expanded = state.expanded + unpacked.length()
      let tag = tag(unpacked, 0, unpacked.length(), little)
      if tag.kind != 14 || tag.next != unpacked.length() {
        fail(
          "invalid-compressed",
          outer.start,
          "Expected exactly one compressed matrix",
        )
      }
      let info = root_info(unpacked, tag, little, basic, true)
      ignore(
        visit_node(unpacked, tag, little, basic, tree, state.budget, 1, false),
      )
      let keep = match wanted {
        None => true
        Some(map) => map.contains(info.name)
      }
      let node = if keep {
        state.result(source_node_size(unpacked, tag, little, basic), true)
        visit_node(
          unpacked,
          tag,
          little,
          basic,
          tree,
          { nodes: 0, elements: 0, metadata: 0, metadata_limit: 0, },
          1,
          true,
        )
      } else {
        None
      }
      (node, info)
    } else {
      fail("unsupported-element", outer.start, "Unsupported root element")
      abort("unreachable")
    }
    if seen.contains(root.name) {
      fail("duplicate-name", outer.start, "Duplicate root")
    }
    seen[root.name] = true
    if node is Some(value) {
      variables.push(value)
      kept[root.name] = value
    }
    if collect {
      roots.push(root)
    }
    count = count + 1
  }
  let ordered = if selection is Some(names) {
    let out = []
    let requested : Map[String, Bool] = Map([])
    for name in names {
      if requested.contains(name) {
        fail("duplicate-name", 0, "Repeated selection")
      }
      requested[name] = true
      match kept.get(name) {
        Some(n) => out.push(n)
        None => fail("missing-variable", 0, "Missing variable: " + name)
      }
    }
    out
  } else {
    variables
  }
  ({ ..file, variables: ordered, }, roots)
}
