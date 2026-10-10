///|
priv struct NpyHeaderCursor {
  bytes : Bytes
  end : Int
  mut position : Int
}

///|
fn NpyHeaderCursor::peek(self : NpyHeaderCursor) -> Byte {
  if self.position < self.end {
    self.bytes[self.position]
  } else {
    b'\x00'
  }
}

///|
fn NpyHeaderCursor::space(self : NpyHeaderCursor) -> Unit {
  while self.position < self.end {
    match self.peek() {
      b' ' | b'\t' | b'\r' | b'\n' => self.position = self.position + 1
      _ => break
    }
  }
}

///|
fn NpyHeaderCursor::expect(
  self : NpyHeaderCursor,
  byte : Byte,
) -> Unit raise MatError {
  if self.position >= self.end || self.peek() != byte {
    fail("invalid-npy", self.position, "Malformed NPY header literal")
  }
  self.position = self.position + 1
}

///|
fn NpyHeaderCursor::literal(
  self : NpyHeaderCursor,
  text : Bytes,
) -> Unit raise MatError {
  for byte in text {
    self.expect(byte)
  }
}

///|
fn NpyHeaderCursor::string(self : NpyHeaderCursor) -> String raise MatError {
  let quote = self.peek()
  if quote.to_int() != 39 && quote.to_int() != 34 {
    fail("invalid-npy", self.position, "Expected plain ASCII NPY string")
  }
  self.expect(quote)
  let start = self.position
  while self.position < self.end && self.peek() != quote {
    let byte = self.peek().to_int()
    if byte < 32 || byte > 126 || byte == 92 {
      fail(
        "invalid-npy",
        self.position,
        "Only plain ASCII header strings are supported",
      )
    }
    self.position = self.position + 1
  }
  let finish = self.position
  self.expect(quote)
  @utf8.decode(self.bytes[start:finish]) catch {
    _ => {
      fail("invalid-npy", start, "Invalid header string")
      ""
    }
  }
}

///|
fn NpyHeaderCursor::dimensions(
  self : NpyHeaderCursor,
  max_rank : Int,
) -> Array[Int] raise MatError {
  self.expect(b'(')
  self.space()
  let shape = []
  if self.peek() == b')' {
    self.expect(b')')
    return shape
  }
  while true {
    if shape.length() >= max_rank {
      fail("invalid-shape", self.position, "NPY rank exceeds configured limit")
    }
    let mut dimension = 0
    let start = self.position
    while self.peek() >= b'0' && self.peek() <= b'9' {
      let digit = self.peek().to_int() - 48
      if dimension > (2147483647 - digit) / 10 {
        fail(
          "invalid-shape",
          self.position,
          "NPY dimension exceeds signed 32-bit range",
        )
      }
      dimension = dimension * 10 + digit
      self.position = self.position + 1
    }
    if self.position == start {
      fail("invalid-npy", start, "Expected nonnegative NPY dimension")
    }
    shape.push(dimension)
    self.space()
    if self.peek() == b')' {
      if shape.length() == 1 {
        fail(
          "invalid-npy",
          self.position,
          "One-dimensional shape requires a tuple comma",
        )
      }
      self.expect(b')')
      break
    }
    self.expect(b',')
    self.space()
    if self.peek() == b')' {
      self.expect(b')')
      break
    }
  }
  shape
}

///|
/// Read primitive numeric NPY v1/v2/v3, normalize endian and C/Fortran order.
/// Scalar and vector NPY shapes become [1,1] and [n,1] for MAT interoperability.
/// No Python expressions or pickle/object payloads are evaluated.
pub fn read_npy(
  bytes : Bytes,
  name : String,
  limits? : Limits = default_limits(),
) -> NumericArray raise MatError {
  validate_limits(limits)
  validate_name(name, limits)
  if bytes.length() > limits.max_file_bytes {
    fail("file-limit", 0, "NPY input exceeds max_file_bytes")
  }
  if bytes.length() < 10 || bytes[0:6] != b"\x93NUMPY" {
    fail("invalid-npy", 0, "Missing or truncated NPY signature")
  }
  let major = bytes[6].to_int()
  if (major != 1 && major != 2 && major != 3) || bytes[7] != b'\x00' {
    fail(
      "unsupported-npy-version", 6, "Supported NPY versions are 1.0, 2.0 and 3.0",
    )
  }
  let prefix = if major == 1 { 10 } else { 12 }
  if bytes.length() < prefix {
    fail("invalid-npy", 8, "Truncated NPY header length")
  }
  let header_size = bits_at(bytes, 8, prefix - 8, true)
  if header_size == 0UL || header_size > 65536UL {
    fail("npy-header-limit", 8, "Numeric NPY headers must fit 64 KiB")
  }
  let end = prefix + header_size.to_int()
  if end > bytes.length() || end % 16 != 0 || bytes[end - 1] != b'\n' {
    fail(
      "invalid-npy", prefix, "Truncated, unaligned or unterminated NPY header",
    )
  }
  let cursor : NpyHeaderCursor = { bytes, end, position: prefix, }
  cursor.space()
  cursor.expect(b'{')
  let seen : Map[String, Bool] = Map([])
  let mut descriptor : String? = None
  let mut fortran : Bool? = None
  let mut dimensions : Array[Int]? = None
  cursor.space()
  while cursor.peek() != b'}' {
    let key = cursor.string()
    if seen.contains(key) {
      fail("invalid-npy", cursor.position, "Duplicate NPY header key")
    }
    seen[key] = true
    cursor.space()
    cursor.expect(b':')
    cursor.space()
    match key {
      "descr" => descriptor = Some(cursor.string())
      "fortran_order" =>
        if cursor.peek() == b'T' {
          cursor.literal(b"True")
          fortran = Some(true)
        } else {
          cursor.literal(b"False")
          fortran = Some(false)
        }
      "shape" => dimensions = Some(cursor.dimensions(limits.max_dimensions))
      _ => fail("invalid-npy", cursor.position, "Unknown NPY header key")
    }
    cursor.space()
    if cursor.peek() == b'}' {
      break
    }
    cursor.expect(b',')
    cursor.space()
  }
  cursor.expect(b'}')
  cursor.space()
  if cursor.position != end || seen.length() != 3 {
    fail(
      "invalid-npy",
      cursor.position,
      "Header must contain exactly descr, fortran_order and shape",
    )
  }
  let descriptor = descriptor.unwrap_or("")
  let dtype = match descriptor {
    "<f8" | ">f8" | "<c16" | ">c16" => Float64
    "<f4" | ">f4" | "<c8" | ">c8" => Float32
    "|i1" | "<i1" | ">i1" => Int8
    "|u1" | "<u1" | ">u1" => UInt8
    "<i2" | ">i2" => Int16
    "<u2" | ">u2" => UInt16
    "<i4" | ">i4" => Int32
    "<u4" | ">u4" => UInt32
    "<i8" | ">i8" => Int64
    "<u8" | ">u8" => UInt64
    "|b1" | "<b1" | ">b1" => Logical
    _ => {
      fail(
        "unsupported-npy-dtype", prefix, "Only primitive numerical/logical dtypes are supported",
      )
      Float64
    }
  }
  let complex = descriptor == "<c8" ||
    descriptor == ">c8" ||
    descriptor == "<c16" ||
    descriptor == ">c16"
  let encoded_descriptor = @utf8.encode(descriptor[:])
  let little = encoded_descriptor[0] != b'>'
  let original_shape = dimensions.unwrap_or([])
  let shape = match original_shape.length() {
    0 => [1, 1]
    1 => [original_shape[0], 1]
    _ => original_shape.copy()
  }
  let count = element_count(shape, limits, prefix)
  let width = dtype.width()
  let item_width = width * (if complex { 2 } else { 1 })
  if count > (limits.max_file_bytes - end) / item_width {
    fail("file-limit", end, "NPY payload exceeds configured byte limit")
  }
  if bytes.length() - end != count * item_width {
    fail(
      "payload-size", end, "NPY payload must exactly match dtype and dimensions",
    )
  }
  let real = Array::make(count * width, b'\x00')
  let imag = if complex { Array::make(count * width, b'\x00') } else { [] }
  let fortran = fortran.unwrap_or(false)
  let c_strides = Array::make(shape.length(), 1)
  if count > 0 {
    for k = shape.length() - 2; k >= 0; k = k - 1 {
      c_strides[k] = c_strides[k + 1] * shape[k + 1]
    }
  }
  for index = 0; index < count; index = index + 1 {
    let mut source = index
    if !fortran {
      let mut remainder = index
      source = 0
      for k = 0; k < shape.length(); k = k + 1 {
        source = source + remainder % shape[k] * c_strides[k]
        remainder = remainder / shape[k]
      }
    }
    for j = 0; j < width; j = j + 1 {
      let offset = end +
        source * item_width +
        (if little { j } else { width - 1 - j })
      let byte = bytes[offset]
      real[index * width + j] = if dtype == Logical && byte != b'\x00' {
        b'\x01'
      } else {
        byte
      }
      if complex {
        imag[index * width + j] = bytes[offset + width]
      }
    }
  }
  raw_array(
    name,
    dtype,
    shape,
    Bytes::from_array(real),
    imag?=if complex { Some(Bytes::from_array(imag)) } else { None },
    limits~,
  )
}
