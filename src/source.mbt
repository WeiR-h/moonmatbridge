///|
/// Host transport fills a caller-owned buffer and returns the number of bytes read.
/// Zero is EOF; negative results indicate I/O failure. The source stays stable for the call.
pub(all) struct MatSource {
  size : Int
  read_into : (Int, FixedArray[Byte], Int, Int) -> Int
}

///|
pub(all) struct SourceLimits {
  max_source_bytes : Int
  max_expanded_bytes : Int
  max_result_bytes : Int
  max_buffered_root_bytes : Int
  max_metadata_bytes : Int
  chunk_bytes : Int
  max_elements : Int
  max_variables : Int
  max_dimensions : Int
  max_name_bytes : Int
} derive(Eq, @debug.Debug)

///|
pub fn default_source_limits() -> SourceLimits {
  {
    max_source_bytes: 1073741824,
    max_expanded_bytes: 1073741824,
    max_result_bytes: 67108864,
    max_buffered_root_bytes: 67108864,
    max_metadata_bytes: 8388608,
    chunk_bytes: 1048576,
    max_elements: 134217728,
    max_variables: 4096,
    max_dimensions: 32,
    max_name_bytes: 1024,
  }
}

///|
fn source_limits(limits : SourceLimits) -> Limits raise MatError {
  for
    n in [
      limits.max_source_bytes,
      limits.max_expanded_bytes,
      limits.max_result_bytes,
      limits.max_buffered_root_bytes,
      limits.max_metadata_bytes,
    ] {
    if n < 128 || n > 1073741824 {
      fail("invalid-limits", 0, "Invalid source byte quota")
    }
  }
  if limits.chunk_bytes < 1 || limits.chunk_bytes > 8388608 {
    fail("invalid-limits", 0, "Chunk size must be 1..8388608")
  }
  let basic : Limits = {
    max_file_bytes: limits.max_source_bytes,
    max_expanded_bytes: limits.max_expanded_bytes,
    max_elements: limits.max_elements,
    max_variables: limits.max_variables,
    max_dimensions: limits.max_dimensions,
    max_name_bytes: limits.max_name_bytes,
  }
  validate_limits(basic)
  basic
}

///|
fn source_fill(
  source : MatSource,
  offset : Int,
  buffer : FixedArray[Byte],
  start : Int,
  length : Int,
  chunk : Int,
) -> Unit raise MatError {
  if offset < 0 ||
    length < 0 ||
    offset > source.size - length ||
    start < 0 ||
    start > buffer.length() - length {
    fail("io-error", offset, "Source read range is invalid")
  }
  let mut done = 0
  while done < length {
    let count = if length - done > chunk { chunk } else { length - done }
    let n = (source.read_into)(offset + done, buffer, start + done, count)
    if n <= 0 || n > count {
      fail(
        "io-error",
        offset + done,
        "Source returned an invalid count or premature EOF",
      )
    }
    done = done + n
  }
}

///|
fn source_bytes(
  source : MatSource,
  offset : Int,
  length : Int,
  chunk : Int,
) -> Bytes raise MatError {
  let out = FixedArray::make(length, b'\x00')
  source_fill(source, offset, out, 0, length, chunk)
  finish_owned_buffer(out)
}

///|
fn source_charge_metadata(
  bytes : Bytes,
  outer : Element,
  little : Bool,
  budget : TreeBudget,
) -> Unit raise MatError {
  let end = outer.start + outer.size
  let flags = tag(bytes, outer.start, end, little)
  let dims = tag(bytes, flags.next, end, little)
  let name = tag(bytes, dims.next, end, little)
  let mut count = dims.size + name.size
  let class = (bits_at(bytes, flags.start, 4, little) & 255UL).to_int()
  let mut position = name.next
  if class == 3 {
    let item = tag(bytes, position, end, little)
    count = count + item.size
    position = item.next
  }
  if class == 2 || class == 3 {
    let width = tag(bytes, position, end, little)
    let fields = tag(bytes, width.next, end, little)
    count = count + fields.size
  }
  if count > budget.metadata_limit - budget.metadata {
    fail(
      "metadata-limit",
      outer.start,
      "Cumulative metadata exceeds source quota",
    )
  }
  budget.metadata = budget.metadata + count
}

///|
/// Called after validation; computes the exact normalized MAT size before materialization.
fn source_node_size(
  bytes : Bytes,
  outer : Element,
  little : Bool,
  limits : Limits,
) -> Int raise MatError {
  if outer.size == 0 {
    return 56
  }
  let end = outer.start + outer.size
  let flags = tag(bytes, outer.start, end, little)
  let bits = bits_at(bytes, flags.start, 4, little).to_uint()
  let class = (bits & 255U).reinterpret_as_int()
  let dims = tag(bytes, flags.next, end, little)
  let name = tag(bytes, dims.next, end, little)
  let shape = Array::makei(dims.size / 4, i => {
    bits_at(bytes, dims.start + 4 * i, 4, little).to_int()
  })
  let mut size = 8 + 16 + element_size(dims.size) + element_size(name.size)
  let mut position = name.next
  if class >= 6 {
    let dtype = if (bits & 512U) != 0U {
      Logical
    } else {
      from_mat_class(class, flags.start)
    }
    let n = element_count(shape, limits, dims.start) * dtype.width()
    return size + element_size(n) * (if (bits & 2048U) != 0U { 2 } else { 1 })
  }
  if class == 5 {
    let rows = tag(bytes, position, end, little)
    let cols = tag(bytes, rows.next, end, little)
    let n = rows.size / 4 * (if (bits & 512U) != 0U { 1 } else { 8 })
    return size +
      element_size(rows.size) +
      element_size(cols.size) +
      element_size(n) * (if (bits & 2048U) != 0U { 2 } else { 1 })
  }
  if class == 4 {
    return size + element_size(tag(bytes, position, end, little).size)
  }
  if class == 3 {
    let item = tag(bytes, position, end, little)
    size = size + element_size(item.size)
    position = item.next
  }
  if class == 2 || class == 3 {
    let width = tag(bytes, position, end, little)
    let step = bits_at(bytes, width.start, 4, little).to_int()
    let fields = tag(bytes, width.next, end, little)
    let mut longest = 1
    for i = 0; i < fields.size / step; i = i + 1 {
      let mut n = 0
      while n < step && bytes[fields.start + i * step + n] != b'\x00' {
        n = n + 1
      }
      if n + 1 > longest {
        longest = n + 1
      }
    }
    size = size + 8 + element_size(longest * (fields.size / step))
    position = fields.next
  }
  while position < end {
    let child = tag(bytes, position, end, little)
    let n = source_node_size(bytes, child, little, limits)
    if n > limits.max_file_bytes - size {
      fail("result-limit", position, "Normalized matrix exceeds result quota")
    }
    size = size + n
    position = child.next
  }
  size
}

///|
fn scan_source(
  source : MatSource,
  selection : Array[String]?,
  collect : Bool,
  limits : SourceLimits,
  tree : TreeLimits,
) -> (MatTree, Array[MatRootInfo]) raise MatError {
  let basic = source_limits(limits)
  validate_tree_limits(tree)
  if source.size < 128 {
    fail("invalid-header", 0, "MAT Level 5 header needs 128 bytes")
  }
  if source.size > limits.max_source_bytes {
    fail("file-limit", 0, "Source exceeds input quota")
  }
  let header = source_bytes(source, 0, 128, limits.chunk_bytes)
  let info = read_tree(header, limits=basic, tree_limits=tree)
  let little = info.little_endian
  let wanted : Map[String, Bool] = Map([])
  if selection is Some(names) {
    for name in names {
      wanted[name] = true
    }
  }
  let seen : Map[String, Bool] = Map([])
  let kept : Map[String, MatNode] = Map([])
  let variables = []
  let roots = []
  let budget : TreeBudget = {
    nodes: 0,
    elements: 0,
    metadata: 0,
    metadata_limit: limits.max_metadata_bytes,
  }
  let mut offset = 128
  let mut expanded = 0
  let mut result_size = 128
  let mut count = 0
  while offset < source.size {
    if count >= limits.max_variables {
      fail("variable-limit", offset, "Too many source roots")
    }
    if source.size - offset < 8 {
      fail("truncated-tag", offset, "Root tag needs eight bytes")
    }
    let tag_bytes = source_bytes(source, offset, 8, limits.chunk_bytes)
    let kind = bits_at(tag_bytes, 0, 4, little)
    let size = bits_at(tag_bytes, 4, 4, little)
    if kind != 14UL && kind != 15UL {
      fail("unsupported-element", offset, "Expected matrix or compressed root")
    }
    let padding = if kind == 15UL { 0UL } else { (8UL - size % 8UL) % 8UL }
    if size + padding > (source.size - offset - 8).to_uint64() {
      fail("truncated-data", offset, "Root exceeds source")
    }
    if size + 8UL + padding > limits.max_buffered_root_bytes.to_uint64() {
      fail("source-buffer-limit", offset, "Root exceeds temporary buffer quota")
    }
    let raw = source_bytes(
      source,
      offset,
      8 + size.to_int() + padding.to_int(),
      limits.chunk_bytes,
    )
    let (bytes, outer) = if kind == 14UL {
      (raw, tag(raw, 0, raw.length(), little))
    } else {
      let available = if limits.max_expanded_bytes - expanded <
        limits.max_buffered_root_bytes {
        limits.max_expanded_bytes - expanded
      } else {
        limits.max_buffered_root_bytes
      }
      let unpacked = inflate_window(
        raw,
        8,
        size.to_int(),
        available,
        Some(little),
      )
      expanded = expanded + unpacked.length()
      let inner = tag(unpacked, 0, unpacked.length(), little)
      if inner.kind != 14 || inner.next != unpacked.length() {
        fail(
          "invalid-compressed", offset, "Compressed root needs exactly one matrix",
        )
      }
      (unpacked, inner)
    }
    let root = root_info(bytes, outer, little, basic, kind == 15UL)
    ignore(visit_node(bytes, outer, little, basic, tree, budget, 1, false))
    if seen.contains(root.name) {
      fail("duplicate-name", offset, "Duplicate source root")
    }
    seen[root.name] = true
    let keep = selection is None || wanted.contains(root.name)
    if keep {
      let n = source_node_size(bytes, outer, little, basic)
      if n > limits.max_result_bytes - result_size {
        fail("result-limit", offset, "Selected normalized MAT exceeds quota")
      }
      result_size = result_size + n
      let materialize_budget : TreeBudget = {
        nodes: 0,
        elements: 0,
        metadata: 0,
        metadata_limit: 0,
      }
      let node = visit_node(
        bytes, outer, little, basic, tree, materialize_budget, 1, true,
      ).unwrap()
      variables.push(node)
      kept[root.name] = node
    }
    if collect {
      roots.push(root)
    }
    offset = offset + raw.length()
    count = count + 1
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
        None => fail("missing-variable", 0, "Missing variable: " + name)
      }
    }
    result
  } else {
    variables
  }
  ({ ..info, variables: ordered, }, roots)
}

///|
pub fn read_tree_from(
  source : MatSource,
  limits? : SourceLimits = default_source_limits(),
  tree_limits? : TreeLimits = default_tree_limits(),
) -> MatTree raise MatError {
  scan_source(source, None, false, limits, tree_limits).0
}

///|
pub fn read_selected_from(
  source : MatSource,
  names : Array[String],
  limits? : SourceLimits = default_source_limits(),
  tree_limits? : TreeLimits = default_tree_limits(),
) -> MatTree raise MatError {
  scan_source(source, Some(names), false, limits, tree_limits).0
}

///|
pub fn inspect_roots_from(
  source : MatSource,
  limits? : SourceLimits = default_source_limits(),
  tree_limits? : TreeLimits = default_tree_limits(),
) -> Array[MatRootInfo] raise MatError {
  scan_source(source, Some([]), true, limits, tree_limits).1
}

///|
pub extend SourceLimits with Eq::{equal, not_equal}

///|
pub extend SourceLimits with @debug.Debug::{to_repr}
