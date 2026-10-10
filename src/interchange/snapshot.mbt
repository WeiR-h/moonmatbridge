///|
fn hex(bytes : Bytes) -> String {
  let digits = b"0123456789abcdef"
  let out = Bytes::makei(bytes.length() * 2, fn(i) {
    let byte = bytes[i / 2].to_int()
    digits[if i % 2 == 0 { byte >> 4 } else { byte & 15 }]
  })
  @utf8.decode_lossy(out[:])
}

///|
fn hex_digit(code : Int) -> Int raise @mat.MatError {
  if code >= 48 && code <= 57 {
    code - 48
  } else if code >= 97 && code <= 102 {
    code - 97 + 10
  } else if code >= 65 && code <= 70 {
    code - 65 + 10
  } else {
    invalid("Raw payload requires hexadecimal pairs")
    0
  }
}

///|
fn unhex(value : Json, limit : Int) -> Bytes raise @mat.MatError {
  let text = string(value)
  if text.length() % 2 != 0 || text.length() / 2 > limit {
    invalid("Hex payload length exceeds bounds or has odd digits")
  }
  let out = []
  for i = 0; i < text.length(); i = i + 2 {
    out.push(
      (hex_digit(text[i].to_int()) * 16 + hex_digit(text[i + 1].to_int())).to_byte(),
    )
  }
  Bytes::from_array(out)
}

///|
fn bounded_integers(
  value : Json,
  maximum : Int,
) -> Array[Int] raise @mat.MatError {
  let values = array(value)
  if values.length() > maximum {
    invalid("Integer vector exceeds configured limit")
  }
  values.map(integer)
}

///|
/// Bit-exact dense/CSC archive. Canonical little-endian planes preserve NaN payloads, signed zero and capacity.
/// This archives array content and flags, not original MAT header text or compression bytes.
pub fn to_snapshot(
  variables : Array[@mat.MatVariable],
  limits? : @mat.Limits = @mat.default_limits(),
) -> String raise @mat.MatError {
  @mat.validate_document(variables, limits~)
  let mut estimate = 128
  // Conservative compact-JSON bound before constructing hex strings or large JSON arrays.
  for variable in variables {
    let (shape, real, imag, indices) = match variable {
      Dense(a) => (a.shape, a.real, a.imag, 0)
      Sparse(a) =>
        (a.shape, a.real, a.imag, a.row_indices.length() + a.col_ptrs.length())
    }
    let overhead = 256 +
      @utf8.encode(variable.name()[:]).length() * 6 +
      shape.length() * 12
    if overhead > limits.max_file_bytes - estimate {
      invalid("Snapshot metadata exceeds byte limit")
    }
    estimate = estimate + overhead
    if indices > (limits.max_file_bytes - estimate) / 12 {
      invalid("Snapshot sparse indices exceed byte limit")
    }
    estimate = estimate + indices * 12
    if real.length() > (limits.max_file_bytes - estimate) / 2 {
      invalid("Snapshot real plane exceeds byte limit")
    }
    estimate = estimate + real.length() * 2
    if imag is Some(bytes) {
      if bytes.length() > (limits.max_file_bytes - estimate) / 2 {
        invalid("Snapshot imaginary plane exceeds byte limit")
      }
      estimate = estimate + bytes.length() * 2
    }
  }
  let entries = variables.map(fn(variable) {
    let (name, dtype, shape, real, imag, global, storage) = match variable {
      Dense(a) =>
        (a.name, a.dtype, a.shape, a.real, a.imag, a.is_global, "dense")
      Sparse(a) =>
        (a.name, a.dtype, a.shape, a.real, a.imag, a.is_global, "csc")
    }
    let fields : Map[String, Json] = Map([
      ("storage", Json::string(storage)),
      ("name", Json::string(name)),
      ("dtype", Json::string(dtype.name())),
      ("shape", Json::array(shape.map(n => Json::number(n.to_double())))),
      ("global", Json::boolean(global)),
      ("real_hex", Json::string(hex(real))),
      ("imag_hex", imag.map(b => Json::string(hex(b))).unwrap_or(Json::null())),
    ])
    if variable is Sparse(a) {
      fields["row_indices"] = Json::array(
        a.row_indices.map(n => Json::number(n.to_double())),
      )
      fields["col_ptrs"] = Json::array(
        a.col_ptrs.map(n => Json::number(n.to_double())),
      )
      fields["nzmax"] = Json::number(a.nzmax.to_double())
    }
    Json::object(fields)
  })
  let text = (
    {
      "schema": "moonmatbridge/snapshot/1",
      "order": "column-major",
      "byte_order": "little",
      "variables": Json::array(entries),
    } : Json).stringify()
  if @utf8.encode(text[:]).length() > limits.max_file_bytes {
    invalid("Encoded snapshot exceeds byte limit")
  }
  text
}

///|
pub fn from_snapshot(
  text : String,
  limits? : @mat.Limits = @mat.default_limits(),
) -> Array[@mat.MatVariable] raise @mat.MatError {
  @mat.validate_document([], limits~)
  if text.length() > limits.max_file_bytes ||
    @utf8.encode(text[:]).length() > limits.max_file_bytes {
    invalid("Snapshot exceeds byte limit")
  }
  let parsed = bounded_parse(text) catch {
    _ => {
      invalid("Malformed snapshot JSON")
      Json::null()
    }
  }
  let root = object(parsed)
  reject_unknown(root, ["schema", "order", "byte_order", "variables"])
  if string(required(root, "schema")) != "moonmatbridge/snapshot/1" ||
    string(required(root, "order")) != "column-major" ||
    string(required(root, "byte_order")) != "little" {
    invalid("Expected canonical moonmatbridge/snapshot/1 archive")
  }
  let entries = array(required(root, "variables"))
  if entries.length() > limits.max_variables {
    invalid("Too many snapshot variables")
  }
  let out = entries.map(entry => {
    let fields = object(entry)
    let storage = string(required(fields, "storage"))
    let allowed = [
      "storage", "name", "dtype", "shape", "global", "real_hex", "imag_hex",
    ]
    if storage == "csc" {
      allowed.push("row_indices")
      allowed.push("col_ptrs")
      allowed.push("nzmax")
    } else if storage != "dense" {
      invalid("Unknown snapshot storage")
    }
    reject_unknown(fields, allowed)
    let name = string(required(fields, "name"))
    let dtype = @mat.dtype_from_name(string(required(fields, "dtype")))
    let shape = bounded_integers(
      required(fields, "shape"),
      limits.max_dimensions,
    )
    let global = match required(fields, "global") {
      True => true
      False => false
      _ => {
        invalid("Global requires boolean")
        false
      }
    }
    let real = unhex(required(fields, "real_hex"), limits.max_file_bytes)
    let imag = match required(fields, "imag_hex") {
      Null => None
      value => Some(unhex(value, limits.max_file_bytes))
    }
    if storage == "dense" {
      @mat.Dense(
        @mat.raw_array(
          name,
          dtype,
          shape,
          real,
          imag?,
          is_global=global,
          limits~,
        ),
      )
    } else {
      @mat.Sparse(
        @mat.raw_sparse_array(
          name,
          dtype,
          shape,
          bounded_integers(required(fields, "row_indices"), limits.max_elements),
          bounded_integers(required(fields, "col_ptrs"), limits.max_elements),
          real,
          imag?,
          nzmax=integer(required(fields, "nzmax")),
          is_global=global,
          limits~,
        ),
      )
    }
  })
  @mat.validate_document(out, limits~)
  out
}
