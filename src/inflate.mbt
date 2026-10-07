///|
/// Original bounded RFC 1950 / RFC 1951 decoder. No platform decompression calls.
priv struct BitReader {
  bytes : Bytes
  end : Int
  mut position : Int
  mut bit : Int
}

///|
fn BitReader::take(self : BitReader, count : Int) -> Int raise MatError {
  let mut value = 0
  for i = 0; i < count; i = i + 1 {
    if self.position >= self.end {
      fail("invalid-zlib", self.position, "Truncated DEFLATE bit stream")
    }
    value = value |
      (((self.bytes[self.position].to_int() >> self.bit) & 1) << i)
    self.bit = self.bit + 1
    if self.bit == 8 {
      self.bit = 0
      self.position = self.position + 1
    }
  }
  value
}

///|
fn BitReader::align(self : BitReader) -> Unit {
  if self.bit != 0 {
    self.bit = 0
    self.position = self.position + 1
  }
}

///|
priv struct Huffman {
  left : Array[Int]
  right : Array[Int]
  symbol : Array[Int]
}

///|
fn huffman(lengths : Array[Int], offset : Int) -> Huffman raise MatError {
  let counts = Array::make(16, 0)
  for length in lengths {
    if length < 0 || length > 15 {
      fail("invalid-zlib", offset, "Invalid Huffman code length")
    }
    if length > 0 {
      counts[length] = counts[length] + 1
    }
  }
  let mut available = 1
  for length = 1; length <= 15; length = length + 1 {
    available = available * 2 - counts[length]
    if available < 0 {
      fail("invalid-zlib", offset, "Oversubscribed Huffman tree")
    }
  }
  let next_code = Array::make(16, 0)
  let mut code = 0
  for length = 1; length <= 15; length = length + 1 {
    code = (code + counts[length - 1]) << 1
    next_code[length] = code
  }
  let tree : Huffman = { left: [-1], right: [-1], symbol: [-1], }
  for symbol = 0; symbol < lengths.length(); symbol = symbol + 1 {
    let length = lengths[symbol]
    if length == 0 {
      continue
    }
    let code = next_code[length]
    next_code[length] = code + 1
    let mut node = 0
    for bit = length - 1; bit >= 0; bit = bit - 1 {
      if tree.symbol[node] >= 0 {
        fail("invalid-zlib", offset, "Conflicting Huffman prefix")
      }
      let right = ((code >> bit) & 1) == 1
      let mut child = if right { tree.right[node] } else { tree.left[node] }
      if child < 0 {
        child = tree.symbol.length()
        tree.left.push(-1)
        tree.right.push(-1)
        tree.symbol.push(-1)
        if right {
          tree.right[node] = child
        } else {
          tree.left[node] = child
        }
      }
      node = child
    }
    if tree.symbol[node] >= 0 || tree.left[node] >= 0 || tree.right[node] >= 0 {
      fail("invalid-zlib", offset, "Conflicting Huffman code")
    }
    tree.symbol[node] = symbol
  }
  tree
}

///|
fn Huffman::decode(self : Huffman, reader : BitReader) -> Int raise MatError {
  let mut node = 0
  for depth = 0; depth <= 15; depth = depth + 1 {
    if self.symbol[node] >= 0 {
      return self.symbol[node]
    }
    if depth == 15 {
      break
    }
    node = if reader.take(1) == 0 { self.left[node] } else { self.right[node] }
    if node < 0 {
      fail("invalid-zlib", reader.position, "Undefined Huffman code")
    }
  }
  fail("invalid-zlib", reader.position, "Huffman code exceeds 15 bits")
  0
}

///|
fn fixed_trees() -> (Huffman, Huffman) raise MatError {
  let literals = Array::makei(288, fn(i) {
    if i <= 143 {
      8
    } else if i <= 255 {
      9
    } else if i <= 279 {
      7
    } else {
      8
    }
  })
  (huffman(literals, 0), huffman(Array::make(32, 5), 0))
}

///|
fn dynamic_trees(reader : BitReader) -> (Huffman, Huffman) raise MatError {
  let literal_count = reader.take(5) + 257
  let distance_count = reader.take(5) + 1
  let code_count = reader.take(4) + 4
  if literal_count > 286 {
    fail("invalid-zlib", reader.position, "Too many literal codes")
  }
  let order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
  let code_lengths = Array::make(19, 0)
  for i = 0; i < code_count; i = i + 1 {
    code_lengths[order[i]] = reader.take(3)
  }
  let codes = huffman(code_lengths, reader.position)
  let lengths : Array[Int] = []
  let count = literal_count + distance_count
  while lengths.length() < count {
    let symbol = codes.decode(reader)
    if symbol <= 15 {
      lengths.push(symbol)
      continue
    }
    let (value, repeats) = match symbol {
      16 => {
        if lengths.is_empty() {
          fail(
            "invalid-zlib",
            reader.position,
            "Repeat code lacks previous length",
          )
        }
        (lengths[lengths.length() - 1], reader.take(2) + 3)
      }
      17 => (0, reader.take(3) + 3)
      18 => (0, reader.take(7) + 11)
      _ => {
        fail("invalid-zlib", reader.position, "Invalid code length symbol")
        (0, 0)
      }
    }
    if repeats > count - lengths.length() {
      fail("invalid-zlib", reader.position, "Code length repeat overruns table")
    }
    for i = 0; i < repeats; i = i + 1 {
      lengths.push(value)
    }
  }
  if lengths[256] == 0 {
    fail("invalid-zlib", reader.position, "Missing end-of-block symbol")
  }
  let literals = Array::makei(literal_count, fn(i) { lengths[i] })
  let distances = Array::makei(distance_count, fn(i) {
    lengths[literal_count + i]
  })
  (huffman(literals, reader.position), huffman(distances, reader.position))
}

///|
fn inflate_codes(
  reader : BitReader,
  out : Array[Byte],
  literals : Huffman,
  distances : Huffman,
  limit : Int,
  window : Int,
) -> Unit raise MatError {
  let length_base = [
    3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67,
    83, 99, 115, 131, 163, 195, 227, 258,
  ]
  let length_extra = [
    0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5,
    5, 5, 0,
  ]
  let distance_base = [
    1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769,
    1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577,
  ]
  let distance_extra = [
    0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11,
    11, 12, 12, 13, 13,
  ]
  while true {
    let symbol = literals.decode(reader)
    if symbol == 256 {
      break
    }
    if symbol < 256 {
      if out.length() >= limit {
        fail(
          "expanded-limit",
          reader.position,
          "Expanded bytes exceed configured limit",
        )
      }
      out.push(symbol.to_byte())
    } else {
      if symbol > 285 {
        fail("invalid-zlib", reader.position, "Reserved length symbol")
      }
      let index = symbol - 257
      let length = length_base[index] + reader.take(length_extra[index])
      let distance_symbol = distances.decode(reader)
      if distance_symbol >= 30 {
        fail("invalid-zlib", reader.position, "Reserved distance symbol")
      }
      let distance = distance_base[distance_symbol] +
        reader.take(distance_extra[distance_symbol])
      if distance > out.length() || distance > window {
        fail(
          "invalid-zlib",
          reader.position,
          "Distance exceeds output or declared zlib window",
        )
      }
      if length > limit - out.length() {
        fail(
          "expanded-limit",
          reader.position,
          "Expanded bytes exceed configured limit",
        )
      }
      for i = 0; i < length; i = i + 1 {
        out.push(out[out.length() - distance])
      }
    }
  }
}

///|
/// Decode a single complete zlib stream. Verifies header, block lengths, stream end and Adler-32.
pub fn inflate_zlib(
  bytes : Bytes,
  max_bytes? : Int = 64 * 1024 * 1024,
) -> Bytes raise MatError {
  if max_bytes < 0 || max_bytes > 1073741824 {
    fail("invalid-limits", 0, "Invalid expanded byte limit")
  }
  if bytes.length() < 6 {
    fail("invalid-zlib", 0, "Truncated zlib header or checksum")
  }
  let cmf = bytes[0].to_int()
  let flags = bytes[1].to_int()
  if (cmf & 15) != 8 || cmf >> 4 > 7 || (cmf * 256 + flags) % 31 != 0 {
    fail("invalid-zlib", 0, "Invalid zlib compression header")
  }
  if (flags & 32) != 0 {
    fail("unsupported-zlib", 1, "Preset dictionaries are not supported")
  }
  let window = 1 << ((cmf >> 4) + 8)
  let reader : BitReader = {
    bytes,
    end: bytes.length() - 4,
    position: 2,
    bit: 0,
  }
  let out : Array[Byte] = []
  let mut last_block = false
  while !last_block {
    last_block = reader.take(1) == 1
    let kind = reader.take(2)
    match kind {
      0 => {
        reader.align()
        let count = reader.take(16)
        let complement = reader.take(16)
        if (count ^ complement) != 65535 {
          fail(
            "invalid-zlib",
            reader.position,
            "Stored block length checksum mismatch",
          )
        }
        if count > max_bytes - out.length() {
          fail(
            "expanded-limit",
            reader.position,
            "Expanded bytes exceed configured limit",
          )
        }
        for i = 0; i < count; i = i + 1 {
          out.push(reader.take(8).to_byte())
        }
      }
      1 => {
        let (literals, distances) = fixed_trees()
        inflate_codes(reader, out, literals, distances, max_bytes, window)
      }
      2 => {
        let (literals, distances) = dynamic_trees(reader)
        inflate_codes(reader, out, literals, distances, max_bytes, window)
      }
      _ => fail("invalid-zlib", reader.position, "Reserved DEFLATE block type")
    }
  }
  reader.align()
  if reader.position != reader.end {
    fail("invalid-zlib", reader.position, "Trailing bytes in zlib stream")
  }
  let mut s1 = 1
  let mut s2 = 0
  for byte in out {
    s1 = (s1 + byte.to_int()) % 65521
    s2 = (s2 + s1) % 65521
  }
  let expected = bits_at(bytes, bytes.length() - 4, 4, false).to_uint()
  let actual = (s2.reinterpret_as_uint() << 16) | s1.reinterpret_as_uint()
  if expected != actual {
    fail("invalid-zlib", bytes.length() - 4, "Adler-32 checksum mismatch")
  }
  Bytes::from_array(out)
}
