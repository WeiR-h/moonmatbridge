///|
/// Export one dense array as NPY v1.0 with fortran_order=True. Complex values are interleaved.
pub fn write_npy(
  array : NumericArray,
  limits? : Limits = default_limits(),
) -> Bytes raise MatError {
  validate_limits(limits)
  ignore(validate_array(array, limits))
  let descriptor = if array.is_complex() {
    if array.dtype == Float64 {
      "<c16"
    } else {
      "<c8"
    }
  } else {
    match array.dtype {
      Float64 => "<f8"
      Float32 => "<f4"
      Int8 => "|i1"
      UInt8 => "|u1"
      Int16 => "<i2"
      UInt16 => "<u2"
      Int32 => "<i4"
      UInt32 => "<u4"
      Int64 => "<i8"
      UInt64 => "<u8"
      Logical => "|b1"
    }
  }
  let dimensions = array.shape.map(fn(n) { n.to_string() }).join(", ")
  let header = "{'descr': '" +
    descriptor +
    "', 'fortran_order': True, 'shape': (" +
    dimensions +
    "), }"
  let header_bytes = @utf8.encode(header[:])
  let padding = (64 - (10 + header_bytes.length() + 1) % 64) % 64
  let header_length = header_bytes.length() + padding + 1
  let data_length = array.real.length() *
    (if array.is_complex() { 2 } else { 1 })
  if header_length > 65535 ||
    data_length > limits.max_file_bytes - 10 - header_length {
    fail("file-limit", 0, "Encoded NPY exceeds configured limit")
  }
  let out = b"\x93NUMPY\x01\x00".to_array()
  push_bits(out, header_length.to_uint64(), 2)
  for byte in header_bytes {
    out.push(byte)
  }
  for i = 0; i < padding; i = i + 1 {
    out.push(b' ')
  }
  out.push(b'\n')
  match array.imag {
    None =>
      for byte in array.real {
        out.push(byte)
      }
    Some(imag) => {
      let width = array.dtype.width()
      for i = 0; i < array.length(); i = i + 1 {
        for j = 0; j < width; j = j + 1 {
          out.push(array.real[i * width + j])
        }
        for j = 0; j < width; j = j + 1 {
          out.push(imag[i * width + j])
        }
      }
    }
  }
  Bytes::from_array(out)
}
