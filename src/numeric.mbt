///|
fn bits_at(bytes : Bytes, offset : Int, width : Int, little : Bool) -> UInt64 {
  let mut bits = 0UL
  for i = 0; i < width; i = i + 1 {
    let index = if little { offset + i } else { offset + width - 1 - i }
    bits = bits | (bytes[index].to_uint64() << (i * 8))
  }
  bits
}

///|
fn push_bits(out : Array[Byte], bits : UInt64, width : Int) -> Unit {
  for i = 0; i < width; i = i + 1 {
    out.push(((bits >> (i * 8)) & 255UL).to_byte())
  }
}

///|
fn scalar_at(
  bytes : Bytes,
  offset : Int,
  dtype : DType,
  little : Bool,
) -> Value {
  let bits = bits_at(bytes, offset, dtype.width(), little)
  match dtype {
    Float64 => Floating(bits.reinterpret_as_double())
    Float32 =>
      Floating(Float::reinterpret_from_uint(bits.to_uint()).to_double())
    Int8 => Signed(bits.reinterpret_as_int64() << 56 >> 56)
    Int16 => Signed(bits.reinterpret_as_int64() << 48 >> 48)
    Int32 => Signed(bits.reinterpret_as_int64() << 32 >> 32)
    Int64 => Signed(bits.reinterpret_as_int64())
    UInt8 | UInt16 | UInt32 | UInt64 => Unsigned(bits)
    Logical => Boolean(bits != 0UL)
  }
}

///|
fn signed_value(
  value : Value,
  low : Int64,
  high : Int64,
  offset : Int,
) -> Int64 raise MatError {
  let result = match value {
    Signed(n) => n
    Unsigned(n) => {
      if n > high.reinterpret_as_uint64() {
        fail("value-range", offset, "Integer exceeds signed type range")
      }
      n.reinterpret_as_int64()
    }
    Boolean(b) => if b { 1L } else { 0L }
    Floating(_) => {
      fail(
        "value-type", offset, "Integer arrays require integer scalars, without floating conversion",
      )
      0L
    }
  }
  if result < low || result > high {
    fail("value-range", offset, "Integer exceeds signed type range")
  }
  result
}

///|
fn unsigned_value(
  value : Value,
  high : UInt64,
  offset : Int,
) -> UInt64 raise MatError {
  let result = match value {
    Unsigned(n) => n
    Signed(n) => {
      if n < 0L {
        fail("value-range", offset, "Negative value for unsigned type")
      }
      n.reinterpret_as_uint64()
    }
    Boolean(b) => if b { 1UL } else { 0UL }
    Floating(_) => {
      fail(
        "value-type", offset, "Integer arrays require integer scalars, without floating conversion",
      )
      0UL
    }
  }
  if result > high {
    fail("value-range", offset, "Integer exceeds unsigned type range")
  }
  result
}

///|
fn floating_value(value : Value, offset : Int) -> Double raise MatError {
  match value {
    Floating(n) => n
    Signed(n) => {
      if n < -9007199254740992L || n > 9007199254740992L {
        fail(
          "precision-loss", offset, "Integer cannot be converted safely to floating point",
        )
      }
      n.to_double()
    }
    Unsigned(n) => {
      if n > 9007199254740992UL {
        fail(
          "precision-loss", offset, "Integer cannot be converted safely to floating point",
        )
      }
      n.to_double()
    }
    Boolean(b) => if b { 1.0 } else { 0.0 }
  }
}

///|
fn append_value(
  out : Array[Byte],
  value : Value,
  dtype : DType,
  offset : Int,
) -> Unit raise MatError {
  let bits = match dtype {
    Float64 => floating_value(value, offset).reinterpret_as_uint64()
    Float32 => {
      let number = floating_value(value, offset)
      let narrow = Float::from_double(number)
      if !number.is_inf() && !number.is_nan() && narrow.to_double().is_inf() {
        fail("value-range", offset, "Finite number overflows float32")
      }
      narrow.reinterpret_as_uint().to_uint64()
    }
    Int8 => signed_value(value, -128L, 127L, offset).reinterpret_as_uint64()
    Int16 =>
      signed_value(value, -32768L, 32767L, offset).reinterpret_as_uint64()
    Int32 =>
      signed_value(value, -2147483648L, 2147483647L, offset).reinterpret_as_uint64()
    Int64 =>
      signed_value(value, -9223372036854775808L, 9223372036854775807L, offset).reinterpret_as_uint64()
    UInt8 => unsigned_value(value, 255UL, offset)
    UInt16 => unsigned_value(value, 65535UL, offset)
    UInt32 => unsigned_value(value, 4294967295UL, offset)
    UInt64 => unsigned_value(value, 18446744073709551615UL, offset)
    Logical =>
      match value {
        Boolean(b) => if b { 1UL } else { 0UL }
        Signed(n) => if n != 0L { 1UL } else { 0UL }
        Unsigned(n) => if n != 0UL { 1UL } else { 0UL }
        Floating(n) => if n != 0.0 { 1UL } else { 0UL }
      }
  }
  push_bits(out, bits, dtype.width())
}

///|
fn validate_name(name : String, limits : Limits) -> Unit raise MatError {
  let bytes = @utf8.encode(name[:])
  if bytes.length() == 0 ||
    bytes.length() > limits.max_name_bytes ||
    name.contains("\u{0000}") {
    fail(
      "invalid-name", 0, "Name must be nonempty UTF-8 without NUL and within max_name_bytes",
    )
  }
}

///|
fn validate_array(array : NumericArray, limits : Limits) -> Int raise MatError {
  validate_name(array.name, limits)
  let count = element_count(array.shape, limits, 0)
  let expected = count * array.dtype.width()
  let planes = if array.is_complex() { 2 } else { 1 }
  if expected > limits.max_file_bytes / planes {
    fail("file-limit", 0, "Array payload exceeds configured file byte limit")
  }
  if array.real.length() != expected {
    fail(
      "payload-size", 0, "Real payload length does not match shape and dtype",
    )
  }
  if array.imag is Some(imag) {
    if array.dtype != Float64 && array.dtype != Float32 {
      fail(
        "unsupported-complex", 0, "Complex arrays require float32 or float64",
      )
    }
    if imag.length() != expected {
      fail(
        "payload-size", 0, "Imaginary payload length does not match real payload",
      )
    }
  }
  if array.dtype == Logical {
    for value in array.real {
      if value != b'\x00' && value != b'\x01' {
        fail(
          "invalid-logical", 0, "Canonical logical payload must contain only 0 or 1",
        )
      }
    }
  }
  count
}

///|
/// Build an array from exact scalar values in column-major order. Float32 conversion rounds to IEEE binary32.
pub fn numeric_array(
  name : String,
  dtype : DType,
  shape : Array[Int],
  values : Array[Value],
  imaginary? : Array[Value],
  is_global? : Bool = false,
  limits? : Limits = default_limits(),
) -> NumericArray raise MatError {
  validate_limits(limits)
  validate_name(name, limits)
  let count = element_count(shape, limits, 0)
  if values.length() != count {
    fail("payload-size", 0, "Value count does not match shape")
  }
  let planes = if imaginary is Some(_) { 2 } else { 1 }
  if count * dtype.width() > limits.max_file_bytes / planes {
    fail("file-limit", 0, "Array payload exceeds configured file byte limit")
  }
  let real = []
  for value in values {
    append_value(real, value, dtype, 0)
  }
  let imag = match imaginary {
    None => None
    Some(values) => {
      if dtype != Float64 && dtype != Float32 {
        fail("unsupported-complex", 0, "Complex arrays require floating dtype")
      }
      if values.length() != count {
        fail("payload-size", 0, "Imaginary value count does not match shape")
      }
      let bytes = []
      for value in values {
        append_value(bytes, value, dtype, 0)
      }
      Some(Bytes::from_array(bytes))
    }
  }
  {
    name,
    dtype,
    shape: shape.copy(),
    real: Bytes::from_array(real),
    imag,
    is_global,
  }
}

///|
/// Build an array from canonical little-endian raw payload; preserves NaN payload bits and signed zero.
pub fn raw_array(
  name : String,
  dtype : DType,
  shape : Array[Int],
  real : Bytes,
  imag? : Bytes,
  is_global? : Bool = false,
  limits? : Limits = default_limits(),
) -> NumericArray raise MatError {
  validate_limits(limits)
  let result : NumericArray = {
    name,
    dtype,
    shape: shape.copy(),
    real,
    imag,
    is_global,
  }
  ignore(validate_array(result, limits))
  result
}

///|
pub fn NumericArray::value(
  self : NumericArray,
  index : Int,
  imaginary? : Bool = false,
) -> Value raise MatError {
  if index < 0 || index >= self.length() {
    fail("index-range", index, "Scalar index outside array")
  }
  let bytes = if imaginary {
    match self.imag {
      Some(bytes) => bytes
      None => {
        fail("no-imaginary", index, "Array is real")
        self.real
      }
    }
  } else {
    self.real
  }
  scalar_at(bytes, index * self.dtype.width(), self.dtype, true)
}

///|
/// Convert multidimensional zero-based coordinates to a column-major linear index.
pub fn NumericArray::index(
  self : NumericArray,
  coordinates : Array[Int],
) -> Int raise MatError {
  if coordinates.length() != self.shape.length() {
    fail("index-range", 0, "Coordinate rank differs from shape")
  }
  // Revalidate shape, because public fields may have been constructed by callers.
  if validate_array(self, default_limits()) == 0 {
    fail("index-range", 0, "Empty array has no coordinates")
  }
  let mut stride = 1
  let mut index = 0
  for i = 0; i < coordinates.length(); i = i + 1 {
    let coordinate = coordinates[i]
    if coordinate < 0 || coordinate >= self.shape[i] {
      fail("index-range", i, "Coordinate outside dimension")
    }
    index = index + coordinate * stride
    stride = stride * self.shape[i]
  }
  index
}
