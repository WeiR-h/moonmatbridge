///|
priv struct Element {
  kind : Int
  start : Int
  size : Int
  next : Int
}

///|
fn tag(
  bytes : Bytes,
  offset : Int,
  end : Int,
  little : Bool,
) -> Element raise MatError {
  if offset < 0 || end > bytes.length() || end - offset < 8 {
    fail("truncated-tag", offset, "Data element tag needs 8 bytes")
  }
  let word = bits_at(bytes, offset, 4, little).to_uint()
  let small_size = (word >> 16).reinterpret_as_int()
  if small_size != 0 {
    if small_size > 4 {
      fail("invalid-small-tag", offset, "Small data element exceeds 4 bytes")
    }
    let kind = (word & 65535U).reinterpret_as_int()
    if kind == 0 || kind == 14 || kind == 15 {
      fail("invalid-small-tag", offset, "Invalid small data element type")
    }
    return { kind, start: offset + 4, size: small_size, next: offset + 8, }
  }
  let kind = word.reinterpret_as_int()
  let size = bits_at(bytes, offset + 4, 4, little)
  if size > (end - offset - 8).to_uint64() {
    fail(
      "truncated-data", offset, "Data element payload exceeds enclosing stream",
    )
  }
  let size = size.to_int()
  // miCOMPRESSED has no 8-byte padding in MATLAB/SciPy files.
  let padding = if kind == 15 { 0 } else { (8 - size % 8) % 8 }
  let start = offset + 8
  if padding > end - start - size {
    fail("truncated-padding", offset, "Missing data element alignment bytes")
  }
  { kind, start, size, next: start + size + padding, }
}

///|
fn payload(bytes : Bytes, element : Element) -> Bytes {
  bytes[element.start:element.start + element.size].to_owned()
}

///|
fn numeric_payload(
  bytes : Bytes,
  element : Element,
  dtype : DType,
  count : Int,
  little : Bool,
) -> Bytes raise MatError {
  let storage = from_mi_type(element.kind, element.start - 8)
  if element.size != count * storage.width() {
    fail(
      "payload-size",
      element.start,
      "Numeric storage length does not match dimensions",
    )
  }
  // Identical types retain every IEEE bit, including NaN payload and negative zero.
  if storage == dtype {
    if little || storage.width() == 1 {
      return payload(bytes, element)
    }
    return Bytes::makei(element.size, fn(i) {
      let width = storage.width()
      bytes[element.start + i / width * width + width - 1 - i % width]
    })
  }
  let out : Array[Byte] = []
  for i = 0; i < count; i = i + 1 {
    let value = scalar_at(
      bytes,
      element.start + i * storage.width(),
      storage,
      little,
    )
    append_value(out, value, dtype, element.start)
  }
  Bytes::from_array(out)
}

///|
fn matrix(
  bytes : Bytes,
  outer : Element,
  little : Bool,
  limits : Limits,
) -> NumericArray raise MatError {
  let end = outer.start + outer.size
  let flags = tag(bytes, outer.start, end, little)
  if flags.kind != 6 || flags.size != 8 {
    fail("invalid-flags", outer.start, "Expected 8-byte miUINT32 array flags")
  }
  let bits = bits_at(bytes, flags.start, 4, little).to_uint()
  let mut dtype = from_mat_class(
    (bits & 255U).reinterpret_as_int(),
    flags.start,
  )
  if (bits & 0xfffff100U) != 0U ||
    bits_at(bytes, flags.start + 4, 4, little) != 0UL {
    fail(
      "unsupported-flags",
      flags.start,
      "Unknown flags or dense nzmax metadata cannot be preserved",
    )
  }
  if (bits & 512U) != 0 {
    dtype = Logical
  }
  let complex = (bits & 2048U) != 0
  if complex && dtype != Float64 && dtype != Float32 {
    fail(
      "unsupported-complex",
      flags.start,
      "Complex arrays require float32 or float64",
    )
  }
  let dims = tag(bytes, flags.next, end, little)
  if dims.kind != 5 ||
    dims.size < 8 ||
    dims.size % 4 != 0 ||
    dims.size / 4 > limits.max_dimensions {
    fail(
      "invalid-shape",
      flags.next,
      "Expected bounded miINT32 dimension vector",
    )
  }
  let shape = Array::makei(dims.size / 4, fn(i) {
    bits_at(bytes, dims.start + i * 4, 4, little).to_uint().reinterpret_as_int()
  })
  let count = element_count(shape, limits, dims.start)
  let name = tag(bytes, dims.next, end, little)
  if name.kind != 1 || name.size == 0 || name.size > limits.max_name_bytes {
    fail(
      "invalid-name",
      dims.next,
      "Expected bounded nonempty miINT8 variable name",
    )
  }
  let name_text = @utf8.decode(bytes[name.start:name.start + name.size]) catch {
    _ => {
      fail("invalid-name", name.start, "Variable name must be valid UTF-8")
      ""
    }
  }
  validate_name(name_text, limits)
  let real_tag = tag(bytes, name.next, end, little)
  let real = numeric_payload(bytes, real_tag, dtype, count, little)
  let (imag, next) = if complex {
    let imag_tag = tag(bytes, real_tag.next, end, little)
    (
      Some(numeric_payload(bytes, imag_tag, dtype, count, little)),
      imag_tag.next,
    )
  } else {
    (None, real_tag.next)
  }
  if next != end {
    fail(
      "trailing-matrix-data", next, "Unexpected data after dense numeric payload",
    )
  }
  let result : NumericArray = {
    name: name_text,
    dtype,
    shape,
    real,
    imag,
    is_global: (bits & 1024U) != 0,
  }
  ignore(validate_array(result, limits))
  result
}

///|
/// Read dense and CSC sparse MAT Level 5. Unknown classes fail; nothing is silently skipped.
pub fn read_document(
  bytes : Bytes,
  limits? : Limits = default_limits(),
) -> MatDocument raise MatError {
  validate_limits(limits)
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
  let little = if bytes[126] == b'I' && bytes[127] == b'M' {
    true
  } else if bytes[126] == b'M' && bytes[127] == b'I' {
    false
  } else {
    fail("invalid-header", 126, "Invalid endian marker")
    true
  }
  if bits_at(bytes, 124, 2, little) != 256UL {
    fail("unsupported-version", 124, "Expected MAT Level 5 version 0x0100")
  }
  // Subsystem data may encode object/function metadata that v0.0.1 cannot preserve.
  if bits_at(bytes, 116, 8, little) != 0UL {
    fail("unsupported-subsystem", 116, "Subsystem data is unsupported")
  }
  let description = @utf8.decode_lossy(bytes[0:116]).trim().to_owned()
  let arrays : Array[MatVariable] = []
  let names : Map[String, Bool] = Map([])
  let mut offset = 128
  let mut expanded = 0
  let mut elements = 0
  while offset < bytes.length() {
    if arrays.length() >= limits.max_variables {
      fail("variable-limit", offset, "Too many variables")
    }
    let outer = tag(bytes, offset, bytes.length(), little)
    let array = if outer.kind == 14 {
      read_variable(bytes, outer, little, limits)
    } else if outer.kind == 15 {
      let unpacked = inflate_zlib(
        payload(bytes, outer),
        max_bytes=limits.max_expanded_bytes - expanded,
      )
      expanded = expanded + unpacked.length()
      let inner = tag(unpacked, 0, unpacked.length(), little)
      if inner.kind != 14 || inner.next != unpacked.length() {
        fail(
          "invalid-compressed", offset, "Compressed element must contain exactly one miMATRIX",
        )
      }
      read_variable(unpacked, inner, little, limits)
    } else {
      fail(
        "unsupported-element", offset, "Expected miMATRIX or miCOMPRESSED at file level",
      )
      read_variable(bytes, outer, little, limits)
    }
    if names.contains(array.name()) {
      fail("duplicate-name", offset, "Duplicate variable name: " + array.name())
    }
    names[array.name()] = true
    if array.stored_elements() > limits.max_elements - elements {
      fail("element-limit", offset, "Total file elements exceed max_elements")
    }
    elements = elements + array.stored_elements()
    arrays.push(array)
    offset = outer.next
  }
  { description, little_endian: little, variables: arrays, }
}

///|
fn read_variable(
  bytes : Bytes,
  outer : Element,
  little : Bool,
  limits : Limits,
) -> MatVariable raise MatError {
  let flags = tag(bytes, outer.start, outer.start + outer.size, little)
  if flags.kind != 6 || flags.size != 8 {
    fail("invalid-flags", outer.start, "Expected array flags")
  }
  if (bits_at(bytes, flags.start, 4, little).to_uint() & 255U) == 5U {
    Sparse(sparse_matrix(bytes, outer, little, limits))
  } else {
    Dense(matrix(bytes, outer, little, limits))
  }
}

///|
/// Compatibility API for dense-only consumers. Sparse variables fail explicitly; use read_document for mixed files.
pub fn read_mat(
  bytes : Bytes,
  limits? : Limits = default_limits(),
) -> MatFile raise MatError {
  let document = read_document(bytes, limits~)
  let arrays = document.variables.map(item => {
    match item {
      Dense(a) => a
      Sparse(_) => {
        fail("unsupported-class", 0, "Sparse variable requires read_document")
        abort("unreachable")
      }
    }
  })
  {
    description: document.description,
    little_endian: document.little_endian,
    arrays,
  }
}
