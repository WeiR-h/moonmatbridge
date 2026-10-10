///|
priv struct BitWriter {
  out : Array[Byte]
  mut pending : Int
  mut count : Int
  limit : Int
}

///|
fn smaller(a : Int, b : Int) -> Int {
  if a < b {
    a
  } else {
    b
  }
}

///|
fn BitWriter::put(
  self : BitWriter,
  value : Int,
  count : Int,
) -> Unit raise MatError {
  self.pending = self.pending | (value << self.count)
  self.count = self.count + count
  while self.count >= 8 {
    if self.out.length() >= self.limit {
      fail("file-limit", 0, "Compressed output exceeds byte limit")
    }
    self.out.push((self.pending & 255).to_byte())
    self.pending = self.pending >> 8
    self.count = self.count - 8
  }
}

///|
fn reverse_code(code : Int, count : Int) -> Int {
  let mut result = 0
  for i = 0; i < count; i = i + 1 {
    result = (result << 1) | ((code >> i) & 1)
  }
  result
}

///|
fn BitWriter::literal(self : BitWriter, symbol : Int) -> Unit raise MatError {
  let (code, count) = if symbol <= 143 {
    (48 + symbol, 8)
  } else if symbol <= 255 {
    (400 + symbol - 144, 9)
  } else if symbol <= 279 {
    (symbol - 256, 7)
  } else {
    (192 + symbol - 280, 8)
  }
  self.put(reverse_code(code, count), count)
}

///|
fn BitWriter::match_code(
  self : BitWriter,
  length : Int,
  distance : Int,
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
  let mut index = 0
  while index < 28 && length >= length_base[index + 1] {
    index = index + 1
  }
  self.literal(257 + index)
  self.put(length - length_base[index], length_extra[index])
  let mut index = 0
  while index < 29 && distance >= distance_base[index + 1] {
    index = index + 1
  }
  self.put(reverse_code(index, 5), 5)
  self.put(distance - distance_base[index], distance_extra[index])
}

///|
fn adler32(bytes : Bytes) -> UInt {
  let mut s1 = 1
  let mut s2 = 0
  for byte in bytes {
    s1 = (s1 + byte.to_int()) % 65521
    s2 = (s2 + s1) % 65521
  }
  (s2.reinterpret_as_uint() << 16) | s1.reinterpret_as_uint()
}

///|
fn append_adler(out : Array[Byte], bytes : Bytes) -> Unit {
  let sum = adler32(bytes)
  for i = 3; i >= 0; i = i - 1 {
    out.push(((sum >> (i * 8)) & 255U).to_byte())
  }
}

///|
fn stored_zlib(bytes : Bytes, limit : Int) -> Bytes raise MatError {
  let blocks = if bytes.length() == 0 {
    1
  } else {
    (bytes.length() + 65534) / 65535
  }
  if bytes.length() + blocks * 5 + 6 > limit {
    fail("file-limit", 0, "Stored zlib stream exceeds output limit")
  }
  let out = [b'\x78', b'\x01']
  let mut offset = 0
  for block = 0; block < blocks; block = block + 1 {
    let size = smaller(65535, bytes.length() - offset)
    out.push(if block == blocks - 1 { b'\x01' } else { b'\x00' })
    push_bits(out, size.to_uint64(), 2)
    push_bits(out, (65535 - size).to_uint64(), 2)
    for i = 0; i < size; i = i + 1 {
      out.push(bytes[offset + i])
    }
    offset = offset + size
  }
  append_adler(out, bytes)
  Bytes::from_array(out)
}

///|
fn fixed_zlib(bytes : Bytes, limit : Int) -> Bytes raise MatError {
  let writer : BitWriter = {
    out: [b'\x78', b'\x01'],
    pending: 0,
    count: 0,
    limit: limit - 4,
  }
  writer.put(3, 3) // final block, fixed Huffman coding
  let heads = Array::make(32768, -1)
  let previous = Array::make(32768, -1)
  let hash = fn(offset : Int) {
    (
      (bytes[offset].to_int() * 251 + bytes[offset + 1].to_int()) * 251 +
      bytes[offset + 2].to_int()
    ) &
    32767
  }
  let insert = fn(position : Int) {
    if position + 2 < bytes.length() {
      let key = hash(position)
      previous[position & 32767] = heads[key]
      heads[key] = position
    }
  }
  let mut position = 0
  while position < bytes.length() {
    let mut length = 0
    let mut distance = 0
    if position + 2 < bytes.length() {
      let mut candidate = heads[hash(position)]
      let mut probes = 0
      let maximum = smaller(258, bytes.length() - position)
      while candidate >= 0 &&
            candidate < position &&
            position - candidate <= 32768 &&
            probes < 32 {
        let mut matched = 0
        while matched < maximum &&
              bytes[candidate + matched] == bytes[position + matched] {
          matched = matched + 1
        }
        if matched >= 3 && matched > length {
          length = matched
          distance = position - candidate
          if matched == maximum {
            break
          }
        }
        let older = previous[candidate & 32767]
        if older >= candidate {
          break
        }
        candidate = older
        probes = probes + 1
      }
    }
    if length >= 3 {
      writer.match_code(length, distance)
      for i = 0; i < length; i = i + 1 {
        insert(position + i)
      }
      position = position + length
    } else {
      writer.literal(bytes[position].to_int())
      insert(position)
      position = position + 1
    }
  }
  writer.literal(256)
  if writer.count != 0 {
    writer.put(0, 8 - writer.count)
  }
  append_adler(writer.out, bytes)
  Bytes::from_array(writer.out)
}

///|
/// Deterministic bounded zlib writer: greedy LZ77 with fixed Huffman codes, or stored blocks when smaller.
/// Input is bounded to 64 MiB; no external compressor, dictionaries, timestamps or platform variation.
pub fn deflate_zlib(
  bytes : Bytes,
  max_bytes? : Int = 64 * 1024 * 1024,
) -> Bytes raise MatError {
  if max_bytes < 6 || max_bytes > 1073741824 {
    fail("invalid-limits", 0, "Invalid compressed output limit")
  }
  if bytes.length() > 64 * 1024 * 1024 {
    fail("file-limit", 0, "Compressor input exceeds 64 MiB")
  }
  let stored_size = bytes.length() +
    (if bytes.length() == 0 { 1 } else { (bytes.length() + 65534) / 65535 }) * 5 +
    6
  let limit = smaller(max_bytes, stored_size)
  fixed_zlib(bytes, limit) catch {
    error =>
      if error.code() == "file-limit" && stored_size <= max_bytes {
        stored_zlib(bytes, max_bytes)
      } else {
        raise error
      }
  }
}
