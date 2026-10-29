///|
/// Host transport fills a caller-owned buffer and returns the number of bytes read.
/// Zero is EOF; negative results indicate I/O failure. The source stays stable for the call.
pub(all) struct MatSource {
  size : Int32
  read_into : (Int32, FixedArray[Byte], Int32, Int32) -> Int32
}

///|
pub(all) struct SourceLimits {
  max_source_bytes : Int32
  max_expanded_bytes : Int32
  max_result_bytes : Int32
  max_buffered_root_bytes : Int32
  max_metadata_bytes : Int32
  chunk_bytes : Int32
  max_elements : Int32
  max_variables : Int32
  max_dimensions : Int32
  max_name_bytes : Int32
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
  offset : Int32,
  buffer : FixedArray[Byte],
  start : Int32,
  length : Int32,
  chunk : Int32,
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
pub fn read_tree_from(
  source : MatSource,
  limits~ : SourceLimits = default_source_limits(),
  tree_limits~ : TreeLimits = default_tree_limits(),
  name_encoding~ : NameEncoding = Utf8,
) -> MatTree raise MatError {
  scan_source_stream(source, None, false, limits, tree_limits, name_encoding~).0
}

///|
pub fn read_selected_from(
  source : MatSource,
  names : Array[String],
  limits~ : SourceLimits = default_source_limits(),
  tree_limits~ : TreeLimits = default_tree_limits(),
  name_encoding~ : NameEncoding = Utf8,
) -> MatTree raise MatError {
  scan_source_stream(
    source,
    Some(names),
    false,
    limits,
    tree_limits,
    name_encoding~,
  ).0
}

///|
pub fn inspect_roots_from(
  source : MatSource,
  limits~ : SourceLimits = default_source_limits(),
  tree_limits~ : TreeLimits = default_tree_limits(),
  name_encoding~ : NameEncoding = Utf8,
) -> Array[MatRootInfo] raise MatError {
  scan_source_stream(
    source,
    Some([]),
    true,
    limits,
    tree_limits,
    name_encoding~,
  ).1
}

///|
pub extend SourceLimits with Eq::{equal, not_equal}

///|
pub extend SourceLimits with @debug.Debug::{to_repr}
