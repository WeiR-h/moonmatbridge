///|
fn error_code(work : () -> Unit raise MatError) -> String {
  try {
    work()
    "no-error"
  } catch {
    error => error.code()
  }
}

///|
fn tiny() -> Bytes raise MatError {
  write_mat([numeric_array("x", Float64, [1, 1], [Floating(2.5)])])
}

///|
fn changed(bytes : Bytes, offset : Int, value : Byte) -> Bytes {
  let out = bytes.to_array()
  out[offset] = value
  Bytes::from_array(out)
}

///|
test "deterministic MAT writer and column-major coordinates" {
  let array = numeric_array("matrix", Float64, [2, 3], [
    Floating(1.0),
    Floating(2.0),
    Floating(3.0),
    Floating(4.0),
    Floating(5.0),
    Floating(6.0),
  ])
  let first = write_mat([array])
  assert_true(first == write_mat([array]))
  let decoded = read_mat(first).arrays[0]
  assert_true(decoded.shape == [2, 3])
  assert_true(decoded.index([1, 2]) == 5)
  match decoded.value(5) {
    Floating(n) => assert_true(n == 6.0)
    _ => assert_true(false)
  }
}

///|
test "every numeric storage class round-trips exactly" {
  let types = [
    Int8,
    UInt8,
    Int16,
    UInt16,
    Int32,
    UInt32,
    Int64,
    UInt64,
    Float32,
    Float64,
    Logical,
  ]
  for dtype in types {
    let values : Array[Value] = if dtype == Float32 || dtype == Float64 {
      [Floating(-1.5), Floating(0.0), Floating(3.25)]
    } else if dtype == Logical {
      [Boolean(true), Boolean(false), Boolean(true)]
    } else if dtype == UInt8 ||
      dtype == UInt16 ||
      dtype == UInt32 ||
      dtype == UInt64 {
      [Unsigned(0UL), Unsigned(1UL), Unsigned(255UL)]
    } else {
      [Signed(-128L), Signed(0L), Signed(127L)]
    }
    let input = numeric_array(dtype.name(), dtype, [1, 3], values)
    let output = read_mat(write_mat([input])).arrays[0]
    assert_true(output.dtype == dtype && output.real == input.real)
  }
}

///|
test "int64 extremes and uint64 beyond JavaScript safe range retain bits" {
  let signed = numeric_array("i", Int64, [1, 3], [
    Signed(-9223372036854775808L),
    Signed(9223372036854775807L),
    Signed(9007199254740993L),
  ])
  let unsigned = numeric_array("u", UInt64, [1, 3], [
    Unsigned(18446744073709551615UL),
    Unsigned(9007199254740993UL),
    Unsigned(0UL),
  ])
  let output = read_mat(write_mat([signed, unsigned])).arrays
  assert_true(output[0].real == signed.real && output[1].real == unsigned.real)
  match output[0].value(0) {
    Signed(n) => assert_true(n == -9223372036854775808L)
    _ => assert_true(false)
  }
  match output[1].value(0) {
    Unsigned(n) => assert_true(n == 18446744073709551615UL)
    _ => assert_true(false)
  }
}

///|
test "raw IEEE NaN payload negative zero and infinities retain bits" {
  let raw : Array[Byte] = []
  for
    bits in [
      0x7ff800000000002aUL, 0x8000000000000000UL, 0x7ff0000000000000UL, 0xfff0000000000000UL,
    ] {
    push_bits(raw, bits, 8)
  }
  let input = raw_array("ieee", Float64, [1, 4], Bytes::from_array(raw))
  let output = read_mat(write_mat([input])).arrays[0]
  assert_true(output.real == input.real)
}

///|
test "complex float32 and float64 preserve separate components" {
  for dtype in [Float32, Float64] {
    let input = numeric_array(
      "z",
      dtype,
      [2, 1],
      [Floating(1.5), Floating(-2.0)],
      imaginary=[Floating(-0.5), Floating(3.0)],
    )
    let output = read_mat(write_mat([input])).arrays[0]
    assert_true(
      output.real == input.real &&
      output.imag == input.imag &&
      output.is_complex(),
    )
  }
}

///|
test "N-dimensional arrays row vectors and column vectors retain shape" {
  for shape in [[1, 6], [6, 1], [1, 2, 3], [2, 1, 3, 1]] {
    let input = numeric_array("a", Int16, shape, [
      Signed(1L),
      Signed(2L),
      Signed(3L),
      Signed(4L),
      Signed(5L),
      Signed(6L),
    ])
    assert_true(read_mat(write_mat([input])).arrays[0].shape == shape)
  }
}

///|
test "empty arrays and empty MAT file" {
  for shape in [[0, 0], [0, 3], [2, 0, 4]] {
    let array = numeric_array("empty", Float64, shape, [])
    let output = read_mat(write_mat([array])).arrays[0]
    assert_true(output.shape == shape && output.length() == 0)
  }
  assert_true(
    write_mat([]).length() == 128 && read_mat(write_mat([])).arrays.is_empty(),
  )
}

///|
test "global flag and UTF-8 variable name" {
  let input = numeric_array(
    "实验数据",
    Float64,
    [1, 1],
    [Floating(1.0)],
    is_global=true,
  )
  let output = read_mat(write_mat([input])).arrays[0]
  assert_true(output.name == input.name && output.is_global)
}

///|
test "new arrays reject negative dimension mismatched payload and rank one" {
  assert_true(
    error_code(() => ignore(numeric_array("a", Float64, [-1, 2], []))) ==
    "invalid-shape",
  )
  assert_true(
    error_code(() => ignore(numeric_array("a", Float64, [2, 2], []))) ==
    "payload-size",
  )
  assert_true(
    error_code(() => ignore(numeric_array("a", Float64, [2], []))) ==
    "invalid-shape",
  )
}

///|
test "checked integer ranges and lossy floating conversion" {
  assert_true(
    error_code(() => ignore(numeric_array("a", Int8, [1, 1], [Signed(128L)]))) ==
    "value-range",
  )
  assert_true(
    error_code(() => ignore(numeric_array("a", UInt8, [1, 1], [Signed(-1L)]))) ==
    "value-range",
  )
  assert_true(
    error_code(() => ignore(numeric_array("a", Int64, [1, 1], [Floating(1.0)]))) ==
    "value-type",
  )
  assert_true(
    error_code(() => {
      ignore(
        numeric_array("a", Float64, [1, 1], [Unsigned(9007199254740993UL)]),
      )
    }) ==
    "precision-loss",
  )
  assert_true(
    error_code(() => {
      ignore(numeric_array("a", Float32, [1, 1], [Floating(1.0e100)]))
    }) ==
    "value-range",
  )
}

///|
test "raw payload validation and logical canonical bytes" {
  assert_true(
    error_code(() => ignore(raw_array("a", Float64, [1, 1], b"x"))) ==
    "payload-size",
  )
  assert_true(
    error_code(() => ignore(raw_array("a", Logical, [1, 1], b"\x02"))) ==
    "invalid-logical",
  )
  assert_true(
    error_code(() => {
      ignore(
        numeric_array("a", Int8, [1, 1], [Signed(1L)], imaginary=[Signed(0L)]),
      )
    }) ==
    "unsupported-complex",
  )
}

///|
test "names cannot be blank contain NUL or exceed limit" {
  assert_true(
    error_code(() => ignore(numeric_array("", Float64, [0, 0], []))) ==
    "invalid-name",
  )
  assert_true(
    error_code(() => ignore(numeric_array("a\u{0000}b", Float64, [0, 0], []))) ==
    "invalid-name",
  )
  let limits = { ..default_limits(), max_name_bytes: 1, }
  assert_true(
    error_code(() => ignore(numeric_array("ab", Float64, [0, 0], [], limits~))) ==
    "invalid-name",
  )
}

///|
test "writer validates public array fields and duplicate names" {
  let good = numeric_array("x", Float64, [1, 1], [Floating(1.0)])
  assert_true(
    error_code(() => ignore(write_mat([good, good]))) == "duplicate-name",
  )
  let bad : NumericArray = { ..good, shape: [2, 2], }
  assert_true(error_code(() => ignore(write_mat([bad]))) == "payload-size")
}

///|
test "shape element variable and file limits enforced" {
  let limits = { ..default_limits(), max_elements: 2, }
  assert_true(
    error_code(() => {
      ignore(numeric_array("a", Float64, [2147483647, 2147483647], [], limits~))
    }) ==
    "element-limit",
  )
  let array = numeric_array("x", Float64, [1, 1], [Floating(1.0)])
  assert_true(
    error_code(() => {
      ignore(
        write_mat([array], limits={ ..default_limits(), max_file_bytes: 128, }),
      )
    }) ==
    "file-limit",
  )
  assert_true(
    error_code(() => {
      ignore(
        read_mat(tiny(), limits={ ..default_limits(), max_file_bytes: 128, }),
      )
    }) ==
    "file-limit",
  )
  assert_true(
    error_code(() => {
      ignore(read_mat(tiny(), limits={ ..default_limits(), max_variables: 0, }))
    }) ==
    "invalid-limits",
  )
}

///|
test "header endian marker version and subsystem errors" {
  let bytes = tiny()
  assert_true(
    error_code(() => ignore(read_mat(changed(bytes, 126, b'X')))) ==
    "invalid-header",
  )
  assert_true(
    error_code(() => ignore(read_mat(changed(bytes, 125, b'\x02')))) ==
    "unsupported-version",
  )
  assert_true(
    error_code(() => ignore(read_mat(changed(bytes, 116, b'\x01')))) ==
    "unsupported-subsystem",
  )
}

///|
test "all truncated prefixes reject cleanly except complete empty header" {
  let bytes = tiny()
  for size = 0; size < bytes.length(); size = size + 1 {
    if size == 128 {
      continue
    }
    assert_true(
      error_code(() => ignore(read_mat(bytes[0:size].to_owned()))) != "no-error",
    )
  }
}

///|
test "unsupported classes tags and malformed small elements reject" {
  let bytes = tiny()
  assert_true(
    error_code(() => ignore(read_mat(changed(bytes, 144, b'\x02')))) ==
    "unsupported-class",
  )
  assert_true(
    error_code(() => ignore(read_mat(changed(bytes, 128, b'\x01')))) ==
    "unsupported-element",
  )
  assert_true(
    error_code(() => ignore(read_mat(changed(bytes, 130, b'\x05')))) ==
    "invalid-small-tag",
  )
}

///|
test "stored DEFLATE block" {
  let compressed = b"\x78\x01\x01\x11\x00\xee\xffhello hello hello\x3a\x2e\x06\x7d"
  assert_true(inflate_zlib(compressed) == b"hello hello hello")
}

///|
test "fixed Huffman block and overlapping backreferences" {
  let compressed = b"\x78\x9c\xcb\x48\xcd\xc9\xc9\x57\xc8\x40\x90\x00\x3a\x2e\x06\x7d"
  assert_true(inflate_zlib(compressed) == b"hello hello hello")
  assert_true(
    error_code(() => ignore(inflate_zlib(compressed, max_bytes=16))) ==
    "expanded-limit",
  )
}

///|
test "zlib checksum header trailing input and truncated stream" {
  let good = b"\x78\x9c\xcb\x48\xcd\xc9\xc9\x57\xc8\x40\x90\x00\x3a\x2e\x06\x7d"
  assert_true(
    error_code(() => ignore(inflate_zlib(changed(good, 15, b'\x00')))) ==
    "invalid-zlib",
  )
  assert_true(
    error_code(() => ignore(inflate_zlib(changed(good, 0, b'\x79')))) ==
    "invalid-zlib",
  )
  assert_true(
    error_code(() => ignore(inflate_zlib(good + b"\x00"))) == "invalid-zlib",
  )
  assert_true(
    error_code(() => ignore(inflate_zlib(b"\x78\x9c"))) == "invalid-zlib",
  )
}

///|
test "NPY header marks Fortran order and interleaves complex payload" {
  let array = numeric_array(
    "z",
    Float64,
    [1, 2],
    [Floating(1.0), Floating(2.0)],
    imaginary=[Floating(3.0), Floating(4.0)],
  )
  let bytes = write_npy(array)
  assert_true(bytes[0:6] == b"\x93NUMPY")
  assert_true(bytes.length() % 16 == 0)
  let start = 10 + bits_at(bytes, 8, 2, true).to_int()
  assert_true(bits_at(bytes, start, 8, true) == 1.0.reinterpret_as_uint64())
  assert_true(bits_at(bytes, start + 8, 8, true) == 3.0.reinterpret_as_uint64())
}

///|
test "coordinate and scalar bounds produce structured errors" {
  let array = numeric_array("a", Float64, [1, 1], [Floating(1.0)])
  assert_true(error_code(() => ignore(array.index([1, 0]))) == "index-range")
  assert_true(error_code(() => ignore(array.value(-1))) == "index-range")
  assert_true(
    error_code(() => ignore(array.value(0, imaginary=true))) == "no-imaginary",
  )
}
