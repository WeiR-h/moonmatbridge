///|
priv struct SourceBits {
  cursor : SourceCursor
  end : Int
  mut position : Int
  mut buffer : Int
  mut available : Int
}

///|
#inline
fn SourceBits::fill(self : SourceBits, count : Int) -> Bool raise MatError {
  while self.available < count && self.position < self.end {
    self.buffer = self.buffer | (self.cursor.byte().to_int() << self.available)
    self.available = self.available + 8
    self.position = self.position + 1
  }
  self.available >= count
}

///|
#inline
fn SourceBits::take(self : SourceBits, count : Int) -> Int raise MatError {
  if !self.fill(count) {
    fail("invalid-zlib", self.position, "Truncated DEFLATE stream")
  }
  let value = self.buffer & ((1 << count) - 1)
  self.buffer = self.buffer >> count
  self.available = self.available - count
  value
}

///|
fn SourceBits::align(self : SourceBits) -> Unit {
  let n = self.available % 8
  self.buffer = self.buffer >> n
  self.available = self.available - n
}

///|
fn Huffman::decode_source(
  self : Huffman,
  reader : SourceBits,
) -> Int raise MatError {
  // At stream end, a valid short symbol may have fewer than nine bits left.
  if reader.fill(9) {
    let entry = self.fast[reader.buffer & 511]
    if entry != 0 {
      ignore(reader.take(entry >> 16))
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
fn source_dynamic_trees(
  reader : SourceBits,
) -> (Huffman, Huffman) raise MatError {
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
    let symbol = codes.decode_source(reader)
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
priv struct SourceInflater {
  reader : SourceBits
  history : FixedArray[Byte]
  window : Int
  maximum : Int
  mut produced : Int
  mut s1 : UInt
  mut s2 : UInt
  mut adler_count : Int
  mut mode : Int
  mut last : Bool
  mut stored : Int
  mut copy : Int
  mut distance : Int
  mut literals : Huffman?
  mut distances : Huffman?
  length_base : Array[Int]
  length_extra : Array[Int]
  distance_base : Array[Int]
  distance_extra : Array[Int]
}

///|
fn make_source_inflater(
  cursor : SourceCursor,
  end : Int,
  maximum : Int,
) -> SourceInflater raise MatError {
  if end - cursor.position < 6 {
    fail("invalid-zlib", cursor.position, "Truncated zlib stream")
  }
  let cmf = cursor.byte().to_int()
  let flags = cursor.byte().to_int()
  if (cmf & 15) != 8 || cmf >> 4 > 7 || (cmf * 256 + flags) % 31 != 0 {
    fail("invalid-zlib", cursor.position - 2, "Invalid zlib header")
  }
  if (flags & 32) != 0 {
    fail(
      "unsupported-zlib",
      cursor.position - 1,
      "Preset dictionary is unsupported",
    )
  }
  {
    length_base: [
      3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67,
      83, 99, 115, 131, 163, 195, 227, 258,
    ],
    length_extra: [
      0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5,
      5, 5, 5, 0,
    ],
    distance_base: [
      1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769,
      1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577,
    ],
    distance_extra: [
      0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11,
      11, 12, 12, 13, 13,
    ],
    reader: {
      cursor,
      end: end - 4,
      position: cursor.position,
      buffer: 0,
      available: 0,
    },
    history: FixedArray::make(32768, b'\x00'),
    window: 1 << ((cmf >> 4) + 8),
    maximum,
    produced: 0,
    s1: 1U,
    s2: 0U,
    adler_count: 0,
    mode: 0,
    last: false,
    stored: 0,
    copy: 0,
    distance: 0,
    literals: None,
    distances: None,
  }
}

///|
#inline
fn SourceInflater::emit(
  self : SourceInflater,
  byte : Byte,
) -> Byte raise MatError {
  if self.produced >= self.maximum {
    fail(
      "expanded-limit",
      self.reader.position,
      "Cumulative expanded bytes exceed quota",
    )
  }
  self.history[self.produced & 32767] = byte
  self.produced = self.produced + 1
  self.s1 = self.s1 + byte.to_uint()
  self.s2 = self.s2 + self.s1
  self.adler_count = self.adler_count + 1
  if self.adler_count == 5552 {
    self.s1 = self.s1 % 65521U
    self.s2 = self.s2 % 65521U
    self.adler_count = 0
  }
  byte
}

///|
fn SourceInflater::finish(self : SourceInflater) -> Unit raise MatError {
  self.reader.align()
  if self.reader.position - self.reader.available / 8 != self.reader.end {
    fail("invalid-zlib", self.reader.position, "Trailing DEFLATE bytes")
  }
  let checksum = self.reader.cursor.owned(4)
  let expected = bits_at(checksum, 0, 4, false).to_uint()
  let actual = ((self.s2 % 65521U) << 16) | (self.s1 % 65521U)
  if actual != expected {
    fail("invalid-zlib", self.reader.position, "Adler32 mismatch")
  }
  self.mode = 3
}

///|
fn SourceInflater::start_copy(
  self : SourceInflater,
  symbol : Int,
) -> Unit raise MatError {
  if symbol > 285 {
    fail("invalid-zlib", self.reader.position, "Reserved length code")
  }
  let i = symbol - 257
  let length = self.length_base[i] + self.reader.take(self.length_extra[i])
  let d = self.distances.unwrap().decode_source(self.reader)
  if d >= 30 {
    fail("invalid-zlib", self.reader.position, "Reserved distance code")
  }
  let distance = self.distance_base[d] +
    self.reader.take(self.distance_extra[d])
  if distance > self.produced || distance > self.window {
    fail(
      "invalid-zlib",
      self.reader.position,
      "Distance exceeds output or declared window",
    )
  }
  if length > self.maximum - self.produced {
    fail("expanded-limit", self.reader.position, "Copy exceeds expansion quota")
  }
  self.copy = length
  self.distance = distance
}

///|
fn SourceInflater::next(self : SourceInflater) -> Byte? raise MatError {
  while true {
    if self.mode == 3 {
      return None
    }
    if self.copy > 0 {
      let byte = self.history[(self.produced - self.distance) & 32767]
      self.copy = self.copy - 1
      return Some(self.emit(byte))
    }
    if self.mode == 0 {
      self.last = self.reader.take(1) == 1
      match self.reader.take(2) {
        0 => {
          self.reader.align()
          let n = self.reader.take(16)
          let inv = self.reader.take(16)
          if (n ^ inv) != 65535 {
            fail(
              "invalid-zlib",
              self.reader.position,
              "Stored block length mismatch",
            )
          }
          if n > self.maximum - self.produced {
            fail(
              "expanded-limit",
              self.reader.position,
              "Stored block exceeds expansion quota",
            )
          }
          self.stored = n
          self.mode = 1
        }
        1 => {
          let (a, b) = fixed_trees()
          self.literals = Some(a)
          self.distances = Some(b)
          self.mode = 2
        }
        2 => {
          let (a, b) = source_dynamic_trees(self.reader)
          self.literals = Some(a)
          self.distances = Some(b)
          self.mode = 2
        }
        _ =>
          fail("invalid-zlib", self.reader.position, "Reserved DEFLATE block")
      }
      continue
    }
    if self.mode == 1 {
      if self.stored > 0 {
        self.stored = self.stored - 1
        return Some(self.emit(self.reader.take(8).to_byte()))
      }
      if self.last {
        self.finish()
        return None
      }
      self.mode = 0
      continue
    }
    let symbol = self.literals.unwrap().decode_source(self.reader)
    if symbol < 256 {
      return Some(self.emit(symbol.to_byte()))
    }
    if symbol == 256 {
      if self.last {
        self.finish()
        return None
      }
      self.mode = 0
      continue
    }
    self.start_copy(symbol)
  } nobreak {
    None
  }
}

///|
fn SourceInflater::fill(
  self : SourceInflater,
  output : FixedArray[Byte],
  count : Int,
) -> Unit raise MatError {
  if count > self.maximum - self.produced {
    fail("expanded-limit", self.reader.position, "Expanded block exceeds quota")
  }
  let mut i = 0
  while i < count {
    if self.copy > 0 {
      let n = if self.copy > count - i { count - i } else { self.copy }
      for j = 0; j < n; j = j + 1 {
        output[i + j] = self.emit(
          self.history[(self.produced - self.distance) & 32767],
        )
      }
      self.copy = self.copy - n
      i = i + n
    } else if self.mode == 1 && self.stored > 0 {
      let n = if self.stored > count - i { count - i } else { self.stored }
      for j = 0; j < n; j = j + 1 {
        output[i + j] = self.emit(self.reader.take(8).to_byte())
      }
      self.stored = self.stored - n
      i = i + n
    } else if self.mode == 2 {
      // The common literal path writes directly into the parser buffer. Only
      // block transitions use next(), avoiding an Option allocation per byte.
      let symbol = self.literals.unwrap().decode_source(self.reader)
      if symbol < 256 {
        output[i] = self.emit(symbol.to_byte())
        i = i + 1
      } else if symbol == 256 {
        if self.last {
          self.finish()
        } else {
          self.mode = 0
        }
      } else {
        self.start_copy(symbol)
      }
    } else {
      match self.next() {
        Some(byte) => {
          output[i] = byte
          i = i + 1
        }
        None =>
          fail(
            "invalid-compressed",
            self.produced,
            "Expanded matrix ends early",
          )
      }
    }
  }
}
