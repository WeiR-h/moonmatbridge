///|
/// Original bounded RFC 1950 / RFC 1951 decoder. No platform decompression calls.
priv struct BitReader {
  bytes : Bytes
  end : Int32
  mut position : Int32
  mut buffer : Int32
  mut available : Int32
}

///|
// Never refill beyond the compressed window or into the Adler checksum.
fn BitReader::fill(self : BitReader, count : Int32) -> Bool {
  while self.available < count && self.position < self.end {
    self.buffer = self.buffer |
      (self.bytes[self.position].to_int() << self.available)
    self.available = self.available + 8
    self.position = self.position + 1
  }
  self.available >= count
}

///|
#inline
fn BitReader::take(self : BitReader, count : Int32) -> Int32 raise MatError {
  if !self.fill(count) {
    fail("invalid-zlib", self.position, "Truncated DEFLATE bit stream")
  }
  let value = self.buffer & ((1 << count) - 1)
  self.buffer = self.buffer >> count
  self.available = self.available - count
  value
}

///|
// Drop padding only; whole prefetched bytes belong to the next block.
fn BitReader::align(self : BitReader) -> Unit {
  let padding = self.available % 8
  self.buffer = self.buffer >> padding
  self.available = self.available - padding
}

///|
priv struct InflateOutput {
  mut data : FixedArray[Byte]
  mut used : Int32
  limit : Int32
  matrix_little : Bool?
  mut hinted : Bool
}

///|
fn InflateOutput::reserve(
  self : InflateOutput,
  additional : Int32,
  offset : Int32,
) -> Unit raise MatError {
  if additional > self.limit - self.used {
    fail("expanded-limit", offset, "Expanded bytes exceed configured limit")
  }
  let needed = self.used + additional
  if needed <= self.data.length() {
    return
  }
  let doubled = if self.data.length() <= self.limit / 2 {
    self.data.length() * 2
  } else {
    self.limit
  }
  let capacity = if needed > doubled { needed } else { doubled }
  let data = FixedArray::make(capacity, b'\x00')
  for i = 0; i < self.used; i = i + 1 {
    data[i] = self.data[i]
  }
  self.data = data
}

///|
// This is an allocation hint, never a substitute for full matrix validation.
fn InflateOutput::matrix_hint(self : InflateOutput) -> Unit {
  if self.hinted || self.used < 8 {
    return
  }
  self.hinted = true
  if self.matrix_little is Some(little) {
    let header = Bytes::makei(8, i => self.data[i])
    if bits_at(header, 0, 4, little) != 14 {
      return
    }
    let size = bits_at(header, 4, 4, little)
    if size > (self.limit - 8).to_uint64() {
      return
    }
    let total = 8 + (size.to_int() + 7) / 8 * 8
    if total <= self.limit && total > self.data.length() {
      let data = FixedArray::make(total, b'\x00')
      for i = 0; i < self.used; i = i + 1 {
        data[i] = self.data[i]
      }
      self.data = data
    }
  }
}

///|
priv struct Huffman {
  left : Array[Int32]
  right : Array[Int32]
  symbol : Array[Int32]
  fast : FixedArray[Int32]
}

///|
fn huffman(lengths : Array[Int32], offset : Int32) -> Huffman raise MatError {
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
  let tree : Huffman = {
    left: [-1],
    right: [-1],
    symbol: [-1],
    fast: FixedArray::make(512, 0),
  }
  for symbol = 0; symbol < lengths.length(); symbol = symbol + 1 {
    let length = lengths[symbol]
    if length == 0 {
      continue
    }
    let code = next_code[length]
    next_code[length] = code + 1
    if length <= 9 {
      let mut reversed = 0
      for i = 0; i < length; i = i + 1 {
        reversed = (reversed << 1) | ((code >> i) & 1)
      }
      for tail = 0; tail < 1 << (9 - length); tail = tail + 1 {
        tree.fast[(tail << length) | reversed] = (length << 16) | (symbol + 1)
      }
    }
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
#inline
fn Huffman::decode(self : Huffman, reader : BitReader) -> Int32 raise MatError {
  // At stream end, a valid short symbol may have fewer than nine bits left.
  if reader.fill(9) {
    let entry = self.fast[reader.buffer & 511]
    if entry != 0 {
      let width = entry >> 16
      reader.buffer = reader.buffer >> width
      reader.available = reader.available - width
      return (entry & 65535) - 1
    }
  }
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
fn make_fixed_trees() -> (Huffman, Huffman) raise MatError {
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
let cached_fixed_trees : (Huffman, Huffman) = make_fixed_trees() catch {
  _ => abort("Invalid built-in Huffman table")
}

///|
fn fixed_trees() -> (Huffman, Huffman) {
  cached_fixed_trees
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
  let lengths : Array[Int32] = []
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
  out : InflateOutput,
  literals : Huffman,
  distances : Huffman,
  window : Int32,
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
  let mut pending = -1
  while true {
    let symbol = if pending >= 0 {
      let value = pending
      pending = -1
      value
    } else {
      literals.decode(reader)
    }
    if symbol == 256 {
      break
    }
    if symbol < 256 {
      out.reserve(1, reader.position)
      let data = out.data
      let mut position = out.used
      let stop = if position < 8 && data.length() > 8 {
        8
      } else {
        data.length()
      }
      data[position] = symbol.to_byte()
      position = position + 1
      while position < stop {
        let next = literals.decode(reader)
        if next >= 256 {
          pending = next
          break
        }
        data[position] = next.to_byte()
        position = position + 1
      }
      out.used = position
      out.matrix_hint()
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
      if distance > out.used || distance > window {
        fail(
          "invalid-zlib",
          reader.position,
          "Distance exceeds output or declared zlib window",
        )
      }
      out.reserve(length, reader.position)
      let begin = out.used
      for i = 0; i < length; i = i + 1 {
        out.data[begin + i] = out.data[begin + i - distance]
      }
      out.used = begin + length
      out.matrix_hint()
    }
  }
}

///|
/// Decode a single complete zlib stream. Verifies header, block lengths, stream end and Adler-32.
pub fn inflate_zlib(
  bytes : Bytes,
  max_bytes~ : Int32 = 64 * 1024 * 1024,
) -> Bytes raise MatError {
  inflate_window(bytes, 0, bytes.length(), max_bytes, None)
}

///|
fn inflate_window(
  bytes : Bytes,
  start : Int32,
  size : Int32,
  max_bytes : Int32,
  matrix_little : Bool?,
) -> Bytes raise MatError {
  if max_bytes < 0 || max_bytes > 1073741824 {
    fail("invalid-limits", 0, "Invalid expanded byte limit")
  }
  if start < 0 || size < 6 || start > bytes.length() - size {
    fail("invalid-zlib", 0, "Truncated zlib header or checksum")
  }
  let cmf = bytes[start].to_int()
  let flags = bytes[start + 1].to_int()
  if (cmf & 15) != 8 || cmf >> 4 > 7 || (cmf * 256 + flags) % 31 != 0 {
    fail("invalid-zlib", 0, "Invalid zlib compression header")
  }
  if (flags & 32) != 0 {
    fail("unsupported-zlib", 1, "Preset dictionaries are not supported")
  }
  let window = 1 << ((cmf >> 4) + 8)
  let reader : BitReader = {
    bytes,
    end: start + size - 4,
    position: start + 2,
    buffer: 0,
    available: 0,
  }
  let out : InflateOutput = {
    data: FixedArray::make(
      if max_bytes < 256 {
        max_bytes
      } else {
        256
      },
      b'\x00',
    ),
    used: 0,
    limit: max_bytes,
    matrix_little,
    hinted: false,
  }
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
        out.reserve(count, reader.position)
        let begin = out.used
        for i = 0; i < count; i = i + 1 {
          out.data[begin + i] = reader.take(8).to_byte()
        }
        out.used = begin + count
        out.matrix_hint()
      }
      1 => {
        let (literals, distances) = fixed_trees()
        inflate_codes(reader, out, literals, distances, window)
      }
      2 => {
        let (literals, distances) = dynamic_trees(reader)
        inflate_codes(reader, out, literals, distances, window)
      }
      _ => fail("invalid-zlib", reader.position, "Reserved DEFLATE block type")
    }
  }
  reader.align()
  if reader.position - reader.available / 8 != reader.end {
    fail("invalid-zlib", reader.position, "Trailing bytes in zlib stream")
  }
  // 5552 bytes keep both Adler accumulators within unsigned 32-bit range.
  let mut s1 : UInt32 = 1
  let mut s2 : UInt32 = 0
  let mut begin = 0
  while begin < out.used {
    let end = if out.used - begin > 5552 { begin + 5552 } else { out.used }
    for i = begin; i < end; i = i + 1 {
      s1 = s1 + out.data[i].to_int().reinterpret_as_uint()
      s2 = s2 + s1
    }
    s1 = s1 % 65521
    s2 = s2 % 65521
    begin = end
  }
  let expected = bits_at(bytes, start + size - 4, 4, false).to_uint()
  let actual = (s2 << 16) | s1
  if expected != actual {
    fail("invalid-zlib", start + size - 4, "Adler-32 checksum mismatch")
  }
  if out.used == out.data.length() {
    return finish_owned_buffer(out.data)
  }
  let data = FixedArray::makei(out.used, i => out.data[i])
  finish_owned_buffer(data)
}
