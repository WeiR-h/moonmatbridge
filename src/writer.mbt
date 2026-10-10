///|
fn append_element(out : Array[Byte], kind : Int, data : Bytes) -> Unit {
  push_bits(out, kind.to_uint64(), 4)
  push_bits(out, data.length().to_uint64(), 4)
  for byte in data {
    out.push(byte)
  }
  let padding = if kind == 15 { 0 } else { (8 - data.length() % 8) % 8 }
  for i = 0; i < padding; i = i + 1 {
    out.push(b'\x00')
  }
}

///|
fn encoded_matrix(array : NumericArray) -> Bytes {
  let out : Array[Byte] = []
  let flags : Array[Byte] = []
  let class = array.dtype.mat_class() +
    (if array.dtype == Logical { 512 } else { 0 }) +
    (if array.is_global { 1024 } else { 0 }) +
    (if array.is_complex() { 2048 } else { 0 })
  push_bits(flags, class.to_uint64(), 4)
  push_bits(flags, 0UL, 4)
  append_element(out, 6, Bytes::from_array(flags))
  let dims : Array[Byte] = []
  for dim in array.shape {
    push_bits(dims, dim.to_uint64(), 4)
  }
  append_element(out, 5, Bytes::from_array(dims))
  append_element(out, 1, @utf8.encode(array.name[:]))
  append_element(out, array.dtype.mi_type(), array.real)
  if array.imag is Some(imag) {
    append_element(out, array.dtype.mi_type(), imag)
  }
  Bytes::from_array(out)
}

///|
/// Calculate validated output size without allocating any MAT payloads.
fn document_size(
  arrays : Array[MatVariable],
  limits : Limits,
) -> Int raise MatError {
  validate_limits(limits)
  if arrays.length() > limits.max_variables {
    fail("variable-limit", 0, "Too many variables")
  }
  let names : Map[String, Bool] = Map([])
  let mut elements = 0
  let mut total = 128
  // Validate and calculate every matrix size before allocating output.
  for variable in arrays {
    let count = match variable { Dense(a) => validate_array(a, limits); Sparse(a) => validate_sparse(a, limits) }
    if count > limits.max_elements - elements {
      fail("element-limit", 0, "Total file elements exceed max_elements")
    }
    elements = elements + count
    if names.contains(variable.name()) {
      fail("duplicate-name", 0, "Duplicate variable name: " + variable.name())
    }
    names[variable.name()] = true
    let name_length = @utf8.encode(variable.name()[:]).length()
    let (rank, payload_length, complex, extra) = match variable {
      Dense(a) => (a.shape.length(), a.real.length(), a.is_complex(), 0)
      Sparse(a) => {
        let rows = a.row_indices.length() * 4
        let cols = a.col_ptrs.length() * 4
        (2, a.real.length(), a.imag is Some(_), 16 + rows + (8 - rows % 8) % 8 + cols + (8 - cols % 8) % 8)
      }
    }
    let matrix_size = 16 +
      8 +
      rank * 4 +
      (8 - rank * 4 % 8) % 8 +
      8 +
      name_length +
      (8 - name_length % 8) % 8 +
      8 +
      payload_length +
      (8 - payload_length % 8) % 8 +
      extra +
      (if complex {
        8 + payload_length + (8 - payload_length % 8) % 8
      } else {
        0
      })
    if matrix_size > limits.max_file_bytes - total - 8 {
      fail("file-limit", 0, "Encoded file exceeds max_file_bytes")
    }
    total = total + matrix_size + 8
  }
  total
}

///|
/// Validate public variable fields, duplicate names and aggregate resource limits without output allocation.
pub fn validate_document(arrays : Array[MatVariable], limits? : Limits = default_limits()) -> Unit raise MatError {
  ignore(document_size(arrays, limits))
}

///|
/// Write deterministic little-endian dense/CSC MAT Level 5, optionally compressed.
pub fn write_document(
  arrays : Array[MatVariable],
  compressed? : Bool = false,
  limits? : Limits = default_limits(),
) -> Bytes raise MatError {
  validate_document(arrays, limits~)
  let out = Array::make(128, b' ')
  let description = "MATLAB 5.0 MAT-file, Created by MoonMatBridge v" + version() + " (MoonBit)"
  let header = @utf8.encode(description[:])
  for i = 0; i < header.length(); i = i + 1 {
    out[i] = header[i]
  }
  for i = 116; i < 126; i = i + 1 {
    out[i] = b'\x00'
  }
  out[125] = b'\x01'
  out[126] = b'I'
  out[127] = b'M'
  let mut expanded = 0
  for variable in arrays {
    let encoded = match variable { Dense(a) => encoded_matrix(a); Sparse(a) => encoded_sparse(a) }
    if compressed {
      let matrix : Array[Byte] = []
      append_element(matrix, 14, encoded)
      if matrix.length() > limits.max_expanded_bytes - expanded {
        fail("expanded-limit", 0, "Matrix exceeds expanded byte limit")
      }
      expanded = expanded + matrix.length()
      let available = limits.max_file_bytes - out.length() - 8
      if available < 6 { fail("file-limit", 0, "No room for compressed matrix") }
      let encoded = deflate_zlib(Bytes::from_array(matrix), max_bytes=available)
      append_element(out, 15, encoded)
    } else {
      append_element(out, 14, encoded)
    }
  }
  Bytes::from_array(out)
}

///|
/// Backwards-compatible dense writer; write_document handles mixed dense/CSC data.
pub fn write_mat(
  arrays : Array[NumericArray],
  compressed? : Bool = false,
  limits? : Limits = default_limits(),
) -> Bytes raise MatError {
  write_document(arrays.map(fn(a) { Dense(a) }), compressed~, limits~)
}
