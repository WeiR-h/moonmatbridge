///|
/// Calculate validated output size without allocating any MAT payloads.
fn document_size(
  arrays : Array[MatVariable],
  limits : Limits,
  name_encoding~ : NameEncoding = Utf8,
) -> Int32 raise MatError {
  validate_limits(limits)
  if arrays.length() > limits.max_variables {
    fail("variable-limit", 0, "Too many variables")
  }
  let names : Map[String, Bool] = Map([])
  let mut elements = 0
  let mut total = 128
  // Validate and calculate every matrix size before allocating output.
  for variable in arrays {
    let count = match variable {
      Dense(a) => validate_array(a, limits, name_encoding~)
      Sparse(a) => validate_sparse(a, limits, name_encoding~)
    }
    if count > limits.max_elements - elements {
      fail("element-limit", 0, "Total file elements exceed max_elements")
    }
    elements = elements + count
    if names.contains(variable.name()) {
      fail("duplicate-name", 0, "Duplicate variable name: " + variable.name())
    }
    names[variable.name()] = true
    let name_length = encode_name(variable.name(), name_encoding).length()
    let (rank, payload_length, complex, extra) = match variable {
      Dense(a) => (a.shape.length(), a.real.length(), a.is_complex(), 0)
      Sparse(a) => {
        let rows = a.row_indices.length() * 4
        let cols = a.col_ptrs.length() * 4
        (
          2,
          a.real.length(),
          a.imag is Some(_),
          16 + rows + (8 - rows % 8) % 8 + cols + (8 - cols % 8) % 8,
        )
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
pub fn validate_document(
  arrays : Array[MatVariable],
  limits~ : Limits = default_limits(),
  name_encoding~ : NameEncoding = Utf8,
) -> Unit raise MatError {
  ignore(document_size(arrays, limits, name_encoding~))
}

///|
/// Write deterministic little-endian dense/CSC MAT Level 5, optionally compressed.
pub fn write_document(
  arrays : Array[MatVariable],
  compressed~ : Bool = false,
  limits~ : Limits = default_limits(),
  name_encoding~ : NameEncoding = Utf8,
) -> Bytes raise MatError {
  validate_document(arrays, limits~, name_encoding~)
  let nodes = arrays.map(fn(item) {
    match item {
      Dense(a) => Numeric(a)
      Sparse(a) => Csc(a)
    }
  })
  write_tree(
    nodes,
    compressed~,
    limits~,
    tree_limits={ ..default_tree_limits(), max_nodes: limits.max_variables, },
    name_encoding~,
  )
}

///|
/// Backwards-compatible dense writer; write_document handles mixed dense/CSC data.
pub fn write_mat(
  arrays : Array[NumericArray],
  compressed~ : Bool = false,
  limits~ : Limits = default_limits(),
  name_encoding~ : NameEncoding = Utf8,
) -> Bytes raise MatError {
  write_document(
    arrays.map(fn(a) { Dense(a) }),
    compressed~,
    limits~,
    name_encoding~,
  )
}
