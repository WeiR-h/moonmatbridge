///|
/// Canonical CSC sparse double/logical matrix. Payload includes all stored slots, including unused capacity.
pub(all) struct SparseArray {
  name : String
  dtype : DType
  shape : Array[Int]
  row_indices : Array[Int]
  col_ptrs : Array[Int]
  real : Bytes
  imag : Bytes?
  nzmax : Int
  is_global : Bool
} derive(@debug.Debug)

///|
pub extend SparseArray with @debug.Debug::{to_repr}

///|
pub(all) enum MatVariable {
  Dense(NumericArray)
  Sparse(SparseArray)
} derive(@debug.Debug)

///|
pub extend MatVariable with @debug.Debug::{to_repr}

///|
pub(all) struct MatDocument {
  description : String
  little_endian : Bool
  variables : Array[MatVariable]
} derive(@debug.Debug)

///|
pub extend MatDocument with @debug.Debug::{to_repr}

///|
pub fn MatVariable::name(self : MatVariable) -> String {
  match self {
    Dense(a) => a.name
    Sparse(a) => a.name
  }
}

///|
pub fn MatVariable::stored_elements(self : MatVariable) -> Int {
  match self {
    Dense(a) => a.length()
    Sparse(a) => a.row_indices.length()
  }
}

///|
/// Number of used CSC entries, including explicit zeros; differs from allocated capacity.
pub fn SparseArray::nnz(self : SparseArray) -> Int {
  self.col_ptrs.get(self.col_ptrs.length() - 1).unwrap_or(0)
}

///|
pub fn MatDocument::get(self : MatDocument, name : String) -> MatVariable? {
  for item in self.variables {
    if item.name() == name {
      return Some(item)
    }
  }
  None
}

///|
pub fn MatDocument::select(
  self : MatDocument,
  names : Array[String],
) -> Array[MatVariable] raise MatError {
  let seen : Map[String, Bool] = Map([])
  let out = []
  for name in names {
    if seen.contains(name) {
      fail("duplicate-name", 0, "Repeated selection: " + name)
    }
    seen[name] = true
    match self.get(name) {
      Some(item) => out.push(item)
      None => fail("missing-variable", 0, "No variable named: " + name)
    }
  }
  out
}

///|
/// Replace one named variable with explicit dense/CSC storage. Other variables remain intact.
pub fn MatDocument::convert_storage(
  self : MatDocument,
  name : String,
  sparse : Bool,
  limits? : Limits = default_limits(),
) -> Array[MatVariable] raise MatError {
  let out = self.variables.copy()
  for i, item in self.variables {
    if item.name() == name {
      out[i] = match (item, sparse) {
        (Dense(a), true) => Sparse(a.to_sparse(limits~))
        (Sparse(a), false) => Dense(a.to_dense(limits~))
        _ => item
      }
      return out
    }
  }
  raise MatError("missing-variable", 0, "No variable named: " + name)
}

///|
fn validate_sparse(a : SparseArray, limits : Limits) -> Int raise MatError {
  validate_name(a.name, limits)
  if a.dtype != Float64 && a.dtype != Logical {
    fail(
      "unsupported-sparse-dtype", 0, "Sparse MAT supports float64 and logical",
    )
  }
  if a.shape.length() != 2 ||
    a.shape[0] < 0 ||
    a.shape[1] < 0 ||
    a.shape[1] >= limits.max_elements {
    fail(
      "invalid-shape", 0, "Sparse shape needs two nonnegative dimensions and bounded column pointers",
    )
  }
  let slots = a.row_indices.length()
  if slots > limits.max_elements ||
    a.nzmax < slots ||
    a.nzmax > limits.max_elements {
    fail(
      "element-limit", 0, "Sparse capacity exceeds configured limit or stored slots",
    )
  }
  if a.col_ptrs.length() != a.shape[1] + 1 ||
    a.col_ptrs[0] != 0 ||
    a.nnz() > slots {
    fail(
      "invalid-sparse", 0, "CSC pointers must start at zero and fit stored slots",
    )
  }
  if a.real.length() != slots * a.dtype.width() {
    fail("payload-size", 0, "Sparse values must match row-index slots")
  }
  if a.imag is Some(imag) &&
    (a.dtype != Float64 || imag.length() != a.real.length()) {
    fail(
      "payload-size", 0, "Sparse complex planes need float64 and equal storage",
    )
  }
  let index_bytes = (slots + a.col_ptrs.length()) * 4
  if index_bytes > limits.max_file_bytes ||
    a.real.length() >
    (limits.max_file_bytes - index_bytes) /
    (if a.imag is Some(_) { 2 } else { 1 }) {
    fail("file-limit", 0, "Sparse payload exceeds byte limit")
  }
  for col = 0; col < a.shape[1]; col = col + 1 {
    let start = a.col_ptrs[col]
    let end = a.col_ptrs[col + 1]
    if start < 0 || end < start || end > slots {
      fail(
        "invalid-sparse", col, "CSC column pointers must be monotone and bounded",
      )
    }
    let mut previous = -1
    for index = start; index < end; index = index + 1 {
      let row = a.row_indices[index]
      if row < 0 || row >= a.shape[0] {
        fail("invalid-sparse", index, "Sparse row is outside dimensions")
      }
      if row <= previous {
        fail(
          "noncanonical-sparse", index, "CSC rows must increase strictly within each column",
        )
      }
      previous = row
    }
  }
  if a.dtype == Logical {
    for value in a.real {
      if value != b'\x00' && value != b'\x01' {
        fail("invalid-logical", 0, "Logical sparse bytes must be 0 or 1")
      }
    }
  }
  slots
}

///|
pub fn raw_sparse_array(
  name : String,
  dtype : DType,
  shape : Array[Int],
  row_indices : Array[Int],
  col_ptrs : Array[Int],
  real : Bytes,
  imag? : Bytes,
  nzmax? : Int,
  is_global? : Bool = false,
  limits? : Limits = default_limits(),
) -> SparseArray raise MatError {
  validate_limits(limits)
  let a : SparseArray = {
    name,
    dtype,
    shape: shape.copy(),
    row_indices: row_indices.copy(),
    col_ptrs: col_ptrs.copy(),
    real,
    imag,
    nzmax: nzmax.unwrap_or(
      if row_indices.is_empty() {
        1
      } else {
        row_indices.length()
      },
    ),
    is_global,
  }
  ignore(validate_sparse(a, limits))
  a
}

///|
/// Explicit densification is bounded by shape product; huge sparse shapes never expand implicitly.
pub fn SparseArray::to_dense(
  self : SparseArray,
  limits? : Limits = default_limits(),
) -> NumericArray raise MatError {
  validate_limits(limits)
  ignore(validate_sparse(self, limits))
  let count = element_count(self.shape, limits, 0)
  let width = self.dtype.width()
  if count * width >
    limits.max_file_bytes / (if self.imag is Some(_) { 2 } else { 1 }) {
    fail("file-limit", 0, "Dense sparse expansion exceeds byte limit")
  }
  let expand = fn(bytes : Bytes) {
    let out = Array::make(count * width, b'\x00')
    for col = 0; col < self.shape[1]; col = col + 1 {
      for index = self.col_ptrs[col]
          index < self.col_ptrs[col + 1]
          index = index + 1 {
        let target = (col * self.shape[0] + self.row_indices[index]) * width
        for j = 0; j < width; j = j + 1 {
          out[target + j] = bytes[index * width + j]
        }
      }
    }
    Bytes::from_array(out)
  }
  {
    name: self.name,
    dtype: self.dtype,
    shape: self.shape.copy(),
    real: expand(self.real),
    imag: self.imag.map(expand),
    is_global: self.is_global,
  }
}

///|
/// Only all-zero byte patterns are omitted. Signed zero, NaN payloads and complex data survive.
pub fn NumericArray::to_sparse(
  self : NumericArray,
  limits? : Limits = default_limits(),
) -> SparseArray raise MatError {
  validate_limits(limits)
  ignore(validate_array(self, limits))
  if self.shape.length() != 2 ||
    (self.dtype != Float64 && self.dtype != Logical) {
    fail(
      "unsupported-sparse-dtype", 0, "Sparse conversion needs two-dimensional float64 or logical",
    )
  }
  if self.shape[1] >= limits.max_elements {
    fail("element-limit", 0, "Too many sparse columns")
  }
  let rows = []
  let cols = [0]
  let real = []
  let imaginary = []
  let width = self.dtype.width()
  for col = 0; col < self.shape[1]; col = col + 1 {
    for row = 0; row < self.shape[0]; row = row + 1 {
      let offset = (col * self.shape[0] + row) * width
      let mut present = false
      for j = 0; j < width; j = j + 1 {
        if self.real[offset + j] != b'\x00' {
          present = true
        }
        if self.imag is Some(bytes) && bytes[offset + j] != b'\x00' {
          present = true
        }
      }
      if present {
        rows.push(row)
        for j = 0; j < width; j = j + 1 {
          real.push(self.real[offset + j])
        }
        if self.imag is Some(bytes) {
          for j = 0; j < width; j = j + 1 {
            imaginary.push(bytes[offset + j])
          }
        }
      }
    }
    cols.push(rows.length())
  }
  let imag = if self.imag is Some(_) {
    Some(Bytes::from_array(imaginary))
  } else {
    None
  }
  raw_sparse_array(
    self.name,
    self.dtype,
    self.shape,
    rows,
    cols,
    Bytes::from_array(real),
    imag?,
    is_global=self.is_global,
    limits~,
  )
}
