///|
fn append_element(out : Array[Byte], kind : Int, data : Bytes) -> Unit {
  push_bits(out, kind.to_uint64(), 4)
  push_bits(out, data.length().to_uint64(), 4)
  for byte in data {
    out.push(byte)
  }
  let padding = (8 - data.length() % 8) % 8
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
/// Write deterministic, uncompressed, little-endian MAT Level 5. No timestamps or lossy numeric casts.
pub fn write_mat(
  arrays : Array[NumericArray],
  limits? : Limits = default_limits(),
) -> Bytes raise MatError {
  validate_limits(limits)
  if arrays.length() > limits.max_variables {
    fail("variable-limit", 0, "Too many variables")
  }
  let names : Map[String, Bool] = Map([])
  let mut elements = 0
  let mut total = 128
  // Validate and calculate every matrix size before allocating output.
  for array in arrays {
    let count = validate_array(array, limits)
    if count > limits.max_elements - elements {
      fail("element-limit", 0, "Total file elements exceed max_elements")
    }
    elements = elements + count
    if names.contains(array.name) {
      fail("duplicate-name", 0, "Duplicate variable name: " + array.name)
    }
    names[array.name] = true
    let name_length = @utf8.encode(array.name[:]).length()
    let payload_length = array.real.length()
    let matrix_size = 16 +
      8 +
      array.shape.length() * 4 +
      (8 - array.shape.length() * 4 % 8) % 8 +
      8 +
      name_length +
      (8 - name_length % 8) % 8 +
      8 +
      payload_length +
      (8 - payload_length % 8) % 8 +
      (if array.is_complex() {
        8 + payload_length + (8 - payload_length % 8) % 8
      } else {
        0
      })
    if matrix_size > limits.max_file_bytes - total - 8 {
      fail("file-limit", 0, "Encoded file exceeds max_file_bytes")
    }
    total = total + matrix_size + 8
  }
  let out = Array::make(128, b' ')
  let header = @utf8.encode(
    "MATLAB 5.0 MAT-file, Created by MoonMatBridge v0.0.1 (MoonBit)"[:],
  )
  for i = 0; i < header.length(); i = i + 1 {
    out[i] = header[i]
  }
  for i = 116; i < 126; i = i + 1 {
    out[i] = b'\x00'
  }
  out[125] = b'\x01'
  out[126] = b'I'
  out[127] = b'M'
  for array in arrays {
    append_element(out, 14, encoded_matrix(array))
  }
  Bytes::from_array(out)
}
