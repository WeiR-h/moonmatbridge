///|
/// Stable JSON wire schema: column-major values, decimal strings for 64-bit integers, explicit non-finites.
pub fn error_json(error : @mat.MatError) -> Json {
  {
    "status": "error",
    "code": error.code(),
    "offset": error.offset(),
    "message": error.message(),
  }
}

///|
fn invalid(message : String) -> Unit raise @mat.MatError {
  raise @mat.MatError("invalid-json", 0, message)
}

///|
fn object(value : Json) -> Map[String, Json] raise @mat.MatError {
  match value {
    Object(map) => map
    _ => {
      invalid("Expected JSON object")
      Map([])
    }
  }
}

///|
fn required(map : Map[String, Json], key : String) -> Json raise @mat.MatError {
  match map.get(key) {
    Some(value) => value
    None => {
      invalid("Missing field: " + key)
      Json::null()
    }
  }
}

///|
fn string(value : Json) -> String raise @mat.MatError {
  match value {
    String(s) => s
    _ => {
      invalid("Expected JSON string")
      ""
    }
  }
}

///|
fn array(value : Json) -> Array[Json] raise @mat.MatError {
  match value {
    Array(a) => a
    _ => {
      invalid("Expected JSON array")
      []
    }
  }
}

///|
fn reject_unknown(
  map : Map[String, Json],
  allowed : Array[String],
) -> Unit raise @mat.MatError {
  for key, _ in map {
    if !allowed.contains(key) {
      invalid("Unknown field: " + key)
    }
  }
}

///|
fn scalar(value : Json, dtype : @mat.DType) -> @mat.Value raise @mat.MatError {
  if dtype == @mat.Int64 || dtype == @mat.UInt64 {
    let text = string(value)
    if text.is_empty() {
      invalid("64-bit integers require decimal strings")
    }
    let start = if text[0] == '-' && dtype == @mat.Int64 { 1 } else { 0 }
    if start == text.length() {
      invalid("Invalid decimal integer")
    }
    for i = start; i < text.length(); i = i + 1 {
      if text[i] < '0' || text[i] > '9' {
        invalid("64-bit integers require base-10 strings")
      }
    }
    return if dtype == @mat.Int64 {
      @mat.Signed(@string.parse_int64(text[:])) catch {
        _ => {
          invalid("Signed 64-bit value out of range")
          @mat.Signed(0L)
        }
      }
    } else {
      @mat.Unsigned(@string.parse_uint64(text[:])) catch {
        _ => {
          invalid("Unsigned 64-bit value out of range")
          @mat.Unsigned(0UL)
        }
      }
    }
  }
  if dtype == @mat.Logical {
    return match value {
      True => @mat.Boolean(true)
      False => @mat.Boolean(false)
      _ => {
        invalid("Logical values must be JSON booleans")
        @mat.Boolean(false)
      }
    }
  }
  if dtype == @mat.Float64 || dtype == @mat.Float32 {
    return match value {
      Number(n, ..) => {
        if n.is_inf() || n.is_nan() {
          invalid("Nonfinite JSON values require explicit string markers")
        }
        @mat.Floating(n)
      }
      String("NaN") => @mat.Floating(@double.not_a_number)
      String("Infinity") => @mat.Floating(@double.infinity)
      String("-Infinity") => @mat.Floating(@double.neg_infinity)
      String("-0") =>
        @mat.Floating(0x8000000000000000UL.reinterpret_as_double())
      _ => {
        invalid(
          "Floating values require numbers, NaN, Infinity, -Infinity or -0",
        )
        @mat.Floating(0.0)
      }
    }
  }
  match value {
    Number(n, ..) => {
      if n.is_nan() ||
        n.is_inf() ||
        n.trunc() != n ||
        n < -2147483648.0 ||
        n > 4294967295.0 {
        invalid("Small integer values require in-range integral JSON numbers")
      }
      @mat.Signed(n.to_int64())
    }
    _ => {
      invalid("Integer values require JSON numbers")
      @mat.Signed(0L)
    }
  }
}

///|
fn scalar_json(value : @mat.Value, dtype : @mat.DType) -> Json {
  match value {
    Signed(n) =>
      if dtype == @mat.Int64 {
        Json::string(n.to_string())
      } else {
        Json::number(n.to_double())
      }
    Unsigned(n) =>
      if dtype == @mat.UInt64 {
        Json::string(n.to_string())
      } else {
        Json::number(n.to_double())
      }
    Boolean(b) => Json::boolean(b)
    Floating(n) =>
      if n.is_nan() {
        Json::string("NaN")
      } else if n.is_pos_inf() {
        Json::string("Infinity")
      } else if n.is_neg_inf() {
        Json::string("-Infinity")
      } else if n.reinterpret_as_uint64() == 0x8000000000000000UL {
        Json::string("-0")
      } else {
        Json::number(n)
      }
  }
}

///| JSON is bounded independently; strict fields catch misspellings rather than dropping scientific metadata.
// This SDK marks the depth option deprecated, but exposes no replacement for a lower bound.

///|
#warnings("-deprecated")
fn bounded_parse(text : String) -> Json raise {
  @json.parse(text[:], max_nesting_depth=64)
}

///|
pub fn from_json(
  text : String,
  limits? : @mat.Limits = @mat.default_limits(),
) -> Array[@mat.NumericArray] raise @mat.MatError {
  if text.length() > limits.max_file_bytes {
    invalid("JSON text exceeds configured limit")
  }
  let document = bounded_parse(text) catch {
    _ => {
      invalid("Malformed JSON or nesting exceeds 64")
      Json::null()
    }
  }
  let root = object(document)
  reject_unknown(root, ["schema", "order", "arrays"])
  if string(required(root, "schema")) != "moonmatbridge/1" ||
    string(required(root, "order")) != "column-major" {
    invalid("Expected schema moonmatbridge/1 with column-major order")
  }
  let arrays = array(required(root, "arrays"))
  if arrays.length() > limits.max_variables {
    invalid("Too many variables")
  }
  let out = []
  let mut total_values = 0
  for entry in arrays {
    let fields = object(entry)
    reject_unknown(fields, ["name", "dtype", "shape", "real", "imag", "global"])
    let dtype = @mat.dtype_from_name(string(required(fields, "dtype")))
    let shape_values = array(required(fields, "shape"))
    if shape_values.length() < 2 ||
      shape_values.length() > limits.max_dimensions {
      invalid("Dimension rank exceeds bounds")
    }
    let shape = shape_values.map(dim => {
      match dim {
        Number(n, ..) => {
          if n < 0.0 || n > 2147483647.0 || n.trunc() != n {
            invalid("Invalid dimension")
          }
          n.to_int()
        }
        _ => {
          invalid("Dimensions require integers")
          0
        }
      }
    })
    let real_values = array(required(fields, "real"))
    if real_values.length() > limits.max_elements - total_values {
      invalid("Total JSON values exceed max_elements")
    }
    total_values = total_values + real_values.length()
    let values = real_values.map(value => scalar(value, dtype))
    let imaginary = match fields.get("imag") {
      None | Some(Null) => None
      Some(value) => {
        let imaginary = array(value)
        if imaginary.length() != values.length() {
          invalid("Imaginary value count differs from real values")
        }
        Some(imaginary.map(value => scalar(value, dtype)))
      }
    }
    let is_global = match fields.get("global") {
      None | Some(False) => false
      Some(True) => true
      _ => {
        invalid("Global flag requires a boolean")
        false
      }
    }
    out.push(
      @mat.numeric_array(
        string(required(fields, "name")),
        dtype,
        shape,
        values,
        imaginary?,
        is_global~,
        limits~,
      ),
    )
  }
  out
}

///|
pub fn to_json(arrays : Array[@mat.NumericArray]) -> Json raise @mat.MatError {
  let entries : Array[Json] = []
  for item in arrays {
    let real = Array::makei(item.length(), i => {
      scalar_json(item.value(i), item.dtype)
    })
    let imaginary : Json = match item.imag {
      None => Json::null()
      Some(_) =>
        Json::array(
          Array::makei(item.length(), i => {
            scalar_json(item.value(i, imaginary=true), item.dtype)
          }),
        )
    }
    let shape = item.shape.map(fn(n) { Json::number(n.to_double()) })
    entries.push({
      "name": item.name,
      "dtype": item.dtype.name(),
      "shape": Json::array(shape),
      "real": Json::array(real),
      "imag": imaginary,
      "global": item.is_global,
    })
  }
  {
    "schema": "moonmatbridge/1",
    "order": "column-major",
    "arrays": Json::array(entries),
  }
}

///|
pub fn info(file : @mat.MatFile) -> Json {
  let entries = file.arrays.map(fn(item) {
    let shape = item.shape.map(fn(n) { Json::number(n.to_double()) })
    (
      {
        "name": item.name,
        "dtype": item.dtype.name(),
        "shape": Json::array(shape),
        "elements": item.length(),
        "complex": item.is_complex(),
        "global": item.is_global,
      } : Json)
  })
  {
    "status": "ok",
    "version": "0.0.1",
    "format": "MAT Level 5",
    "source_endian": if file.little_endian {
      "little"
    } else {
      "big"
    },
    "arrays": Json::array(entries),
  }
}

///|
/// Small reproducible data set used by CLI and cross-language examples.
pub fn sample() -> Array[@mat.NumericArray] raise @mat.MatError {
  [
    @mat.numeric_array("temperature", @mat.Float64, [2, 3], [
      Floating(21.5),
      Floating(22.0),
      Floating(20.25),
      Floating(19.75),
      Floating(18.0),
      Floating(17.5),
    ]),
    @mat.numeric_array(
      "spectrum",
      @mat.Float64,
      [2, 1],
      [Floating(1.0), Floating(0.5)],
      imaginary=[Floating(-2.0), Floating(3.0)],
    ),
    @mat.numeric_array("sample_id", @mat.UInt64, [1, 3], [
      Unsigned(9007199254740993UL),
      Unsigned(18446744073709551615UL),
      Unsigned(0UL),
    ]),
    @mat.numeric_array("valid", @mat.Logical, [2, 1], [
      Boolean(true),
      Boolean(false),
    ]),
  ]
}
