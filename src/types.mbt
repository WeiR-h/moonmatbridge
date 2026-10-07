///|
/// Supported dense array classes. All payloads use little-endian, column-major order.
pub(all) enum DType {
  Float64
  Float32
  Int8
  UInt8
  Int16
  UInt16
  Int32
  UInt32
  Int64
  UInt64
  Logical
} derive(Eq, @debug.Debug)

///|
/// Exact scalar representation; integer values never pass through Double.
pub(all) enum Value {
  Signed(Int64)
  Unsigned(UInt64)
  Floating(Double)
  Boolean(Bool)
} derive(@debug.Debug)

///|
/// Error offsets refer to the current MAT stream, or the expanded stream for compressed data.
pub(all) suberror MatError {
  MatError(String, Int, String)
} derive(Eq, @debug.Debug)

///|
pub fn MatError::code(self : MatError) -> String {
  let MatError(code, _, _) = self
  code
}

///|
pub fn MatError::offset(self : MatError) -> Int {
  let MatError(_, offset, _) = self
  offset
}

///|
pub fn MatError::message(self : MatError) -> String {
  let MatError(_, _, message) = self
  message
}

///|
/// Limits are validated before reading or allocating according to file-controlled lengths.
pub(all) struct Limits {
  max_file_bytes : Int
  max_expanded_bytes : Int
  max_elements : Int
  max_variables : Int
  max_dimensions : Int
  max_name_bytes : Int
} derive(Eq, @debug.Debug)

///|
pub fn default_limits() -> Limits {
  {
    max_file_bytes: 64 * 1024 * 1024,
    max_expanded_bytes: 64 * 1024 * 1024,
    max_elements: 4 * 1024 * 1024,
    max_variables: 4096,
    max_dimensions: 32,
    max_name_bytes: 1024,
  }
}

///|
/// Arrays own their canonical payload. Writers revalidate public fields before serialization.
pub(all) struct NumericArray {
  name : String
  dtype : DType
  shape : Array[Int]
  real : Bytes
  imag : Bytes?
  is_global : Bool
} derive(@debug.Debug)

///|
/// Original file byte order is reported; arrays are normalized to little-endian.
pub(all) struct MatFile {
  description : String
  little_endian : Bool
  arrays : Array[NumericArray]
} derive(@debug.Debug)

///|
fn fail(code : String, offset : Int, message : String) -> Unit raise MatError {
  raise MatError(code, offset, message)
}

///|
fn validate_limits(limits : Limits) -> Unit raise MatError {
  if limits.max_file_bytes < 128 ||
    limits.max_file_bytes > 1073741824 ||
    limits.max_expanded_bytes < 8 ||
    limits.max_expanded_bytes > 1073741824 ||
    limits.max_elements < 1 ||
    limits.max_elements > 134217728 ||
    limits.max_variables < 1 ||
    limits.max_variables > 65536 ||
    limits.max_dimensions < 2 ||
    limits.max_dimensions > 128 ||
    limits.max_name_bytes < 1 ||
    limits.max_name_bytes > 65536 {
    fail(
      "invalid-limits", 0, "Limits must be positive and within documented bounds",
    )
  }
}

///|
pub fn DType::name(self : DType) -> String {
  match self {
    Float64 => "float64"
    Float32 => "float32"
    Int8 => "int8"
    UInt8 => "uint8"
    Int16 => "int16"
    UInt16 => "uint16"
    Int32 => "int32"
    UInt32 => "uint32"
    Int64 => "int64"
    UInt64 => "uint64"
    Logical => "logical"
  }
}

///|
pub fn dtype_from_name(name : String) -> DType raise MatError {
  match name {
    "float64" => Float64
    "float32" => Float32
    "int8" => Int8
    "uint8" => UInt8
    "int16" => Int16
    "uint16" => UInt16
    "int32" => Int32
    "uint32" => UInt32
    "int64" => Int64
    "uint64" => UInt64
    "logical" => Logical
    _ => {
      fail("unsupported-dtype", 0, "Unknown numeric type: " + name)
      Float64
    }
  }
}

///|
pub fn DType::width(self : DType) -> Int {
  match self {
    Float64 | Int64 | UInt64 => 8
    Float32 | Int32 | UInt32 => 4
    Int16 | UInt16 => 2
    Int8 | UInt8 | Logical => 1
  }
}

///|
fn DType::mat_class(self : DType) -> Int {
  match self {
    Float64 => 6
    Float32 => 7
    Int8 => 8
    UInt8 | Logical => 9
    Int16 => 10
    UInt16 => 11
    Int32 => 12
    UInt32 => 13
    Int64 => 14
    UInt64 => 15
  }
}

///|
fn DType::mi_type(self : DType) -> Int {
  match self {
    Int8 => 1
    UInt8 | Logical => 2
    Int16 => 3
    UInt16 => 4
    Int32 => 5
    UInt32 => 6
    Float32 => 7
    Float64 => 9
    Int64 => 12
    UInt64 => 13
  }
}

///|
fn from_mi_type(tag : Int, offset : Int) -> DType raise MatError {
  match tag {
    1 => Int8
    2 => UInt8
    3 => Int16
    4 => UInt16
    5 => Int32
    6 => UInt32
    7 => Float32
    9 => Float64
    12 => Int64
    13 => UInt64
    _ => {
      fail("unsupported-storage", offset, "Unsupported numeric storage tag")
      Float64
    }
  }
}

///|
fn from_mat_class(class : Int, offset : Int) -> DType raise MatError {
  match class {
    6 => Float64
    7 => Float32
    8 => Int8
    9 => UInt8
    10 => Int16
    11 => UInt16
    12 => Int32
    13 => UInt32
    14 => Int64
    15 => UInt64
    _ => {
      fail(
        "unsupported-class", offset, "Only dense numeric and logical arrays are supported",
      )
      Float64
    }
  }
}

///|
fn element_count(
  shape : Array[Int],
  limits : Limits,
  offset : Int,
) -> Int raise MatError {
  if shape.length() < 2 || shape.length() > limits.max_dimensions {
    fail(
      "invalid-shape", offset, "MAT arrays require 2 to max_dimensions dimensions",
    )
  }
  let mut empty = false
  for dim in shape {
    if dim < 0 {
      fail("invalid-shape", offset, "Negative dimension")
    }
    if dim == 0 {
      empty = true
    }
  }
  if empty {
    return 0
  }
  let mut count = 1
  for dim in shape {
    if dim > limits.max_elements / count {
      fail("element-limit", offset, "Dimension product exceeds max_elements")
    }
    count = count * dim
  }
  count
}

///|
pub fn NumericArray::length(self : NumericArray) -> Int {
  self.real.length() / self.dtype.width()
}

///|
pub fn NumericArray::is_complex(self : NumericArray) -> Bool {
  self.imag is Some(_)
}

///|
pub fn MatFile::get(self : MatFile, name : String) -> NumericArray? {
  for array in self.arrays {
    if array.name == name {
      return Some(array)
    }
  }
  None
}

///|
pub extend DType with Eq::{equal, not_equal}

///|
pub extend DType with @debug.Debug::{to_repr}

///|
pub extend Value with @debug.Debug::{to_repr}

///|
pub extend MatError with Eq::{equal, not_equal}

///|
pub extend MatError with @debug.Debug::{to_repr}

///|
pub extend Limits with Eq::{equal, not_equal}

///|
pub extend Limits with @debug.Debug::{to_repr}

///|
pub extend NumericArray with @debug.Debug::{to_repr}

///|
pub extend MatFile with @debug.Debug::{to_repr}
