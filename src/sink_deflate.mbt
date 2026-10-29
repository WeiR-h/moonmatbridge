///|
/// A fixed raw block schedule makes compression independent of sink short writes.
priv struct SinkDeflater {
  output : SinkCursor
  window : FixedArray[Byte]
  heads : FixedArray[Int32]
  previous : FixedArray[Int32]
  total : Int32
  mut received : Int32
  mut used : Int32
  mut history : Int32
  mut pending : Int32
  mut bits : Int32
  mut s1 : Int32
  mut s2 : Int32
}

///|
fn sink_deflate_hash(state : SinkDeflater, at : Int32) -> Int32 {
  (
    (state.window[at].to_int() * 251 + state.window[at + 1].to_int()) * 251 +
    state.window[at + 2].to_int()
  ) &
  32767
}

///|
fn sink_deflate_insert(state : SinkDeflater, at : Int32, end : Int32) -> Unit {
  if at + 2 < end {
    let key = sink_deflate_hash(state, at)
    state.previous[at & 32767] = state.heads[key]
    state.heads[key] = at
  }
}

///|
fn sink_deflate_block(state : SinkDeflater) -> Unit raise MatError {
  let last = state.received == state.total
  let start = state.history
  let end = start + state.used
  for i = 0; i < 32768; i = i + 1 {
    state.heads[i] = -1
    state.previous[i] = -1
  }
  for i = 0; i < start; i = i + 1 {
    sink_deflate_insert(state, i, end)
  }
  let writer : BitWriter = {
    out: [],
    pending: state.pending,
    count: state.bits,
    limit: 80000,
  }
  writer.put(if last { 3 } else { 2 }, 3)
  let mut position = start
  while position < end {
    let mut length = 0
    let mut distance = 0
    if position + 2 < end {
      let mut candidate = state.heads[sink_deflate_hash(state, position)]
      let mut probes = 0
      let maximum = smaller(258, end - position)
      while candidate >= 0 &&
            candidate < position &&
            position - candidate <= 32768 &&
            probes < 32 {
        let mut matched = 0
        while matched < maximum &&
              state.window[candidate + matched] ==
              state.window[position + matched] {
          matched = matched + 1
        }
        if matched >= 3 && matched > length {
          length = matched
          distance = position - candidate
          if matched == maximum {
            break
          }
        }
        let older = state.previous[candidate & 32767]
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
        sink_deflate_insert(state, position + i, end)
      }
      position = position + length
    } else {
      writer.literal(state.window[position].to_int())
      sink_deflate_insert(state, position, end)
      position = position + 1
    }
  }
  writer.literal(256)
  let fixed_bits = writer.out.length() * 8 + writer.count
  let stored_bits = state.bits +
    3 +
    (8 - (state.bits + 3) % 8) % 8 +
    32 +
    state.used * 8
  let fixed_cost = fixed_bits +
    (if last { (8 - fixed_bits % 8) % 8 } else { 0 })
  if fixed_cost <= stored_bits {
    let bytes = Bytes::from_array(writer.out)
    sink_copy(state.output, bytes, 0, bytes.length())
    state.pending = writer.pending
    state.bits = writer.count
  } else {
    let stored : BitWriter = {
      out: [],
      pending: state.pending,
      count: state.bits,
      limit: 16,
    }
    stored.put(if last { 1 } else { 0 }, 3)
    if stored.count != 0 {
      stored.put(0, 8 - stored.count)
    }
    let bytes = Bytes::from_array(stored.out)
    sink_copy(state.output, bytes, 0, bytes.length())
    for i = 0; i < 2; i = i + 1 {
      sink_byte(state.output, ((state.used >> (8 * i)) & 255).to_byte())
    }
    for i = 0; i < 2; i = i + 1 {
      sink_byte(
        state.output,
        (((65535 - state.used) >> (8 * i)) & 255).to_byte(),
      )
    }
    // Private synchronous view: sink_copy copies every byte into its own buffer;
    // this view never escapes or survives the subsequent window update.
    let view = state.window.unsafe_reinterpret_as_bytes()
    sink_copy(state.output, view, start, state.used)
    state.pending = 0
    state.bits = 0
  }
  let keep = smaller(32768, end)
  for i = 0; i < keep; i = i + 1 {
    state.window[i] = state.window[end - keep + i]
  }
  state.history = keep
  state.used = 0
}

///|
fn sink_deflate_feed(
  state : SinkDeflater,
  buffer : FixedArray[Byte],
  count : Int32,
) -> Unit raise MatError {
  if count > state.total - state.received {
    fail("payload-size", 0, "Compressed root exceeds preflight size")
  }
  for i = 0; i < count; i = i + 1 {
    let byte = buffer[i]
    state.window[state.history + state.used] = byte
    state.s1 = (state.s1 + byte.to_int()) % 65521
    state.s2 = (state.s2 + state.s1) % 65521
    state.used = state.used + 1
    state.received = state.received + 1
    if state.used == 65535 || state.received == state.total {
      sink_deflate_block(state)
    }
  }
}

///|
fn sink_compressed_root(
  output : SinkCursor,
  node : MatNode,
  planned : Array[Int32],
  index : Int32,
  root_bytes : Int32,
  encoding : NameEncoding,
  sink : MatSink,
  chunk : Int32,
) -> Unit raise MatError {
  let tag_at = output.offset
  sink_tag(output, 15, 0)
  let stream_at = output.offset
  sink_byte(output, b'\x78')
  sink_byte(output, b'\x01')
  let state : SinkDeflater = {
    output,
    window: FixedArray::make(98303, b'\x00'),
    heads: FixedArray::make(32768, -1),
    previous: FixedArray::make(32768, -1),
    total: root_bytes,
    received: 0,
    used: 0,
    history: 0,
    pending: 0,
    bits: 0,
    s1: 1,
    s2: 0,
  }
  let raw : SinkCursor = {
    buffer: FixedArray::make(smaller(chunk, root_bytes), b'\x00'),
    limit: root_bytes,
    offset: 0,
    used: 0,
    node: index,
    consume: (_, buffer, count) => sink_deflate_feed(state, buffer, count),
  }
  sink_node(raw, node, planned, name_encoding=encoding)
  sink_flush(raw)
  guard! raw.offset == root_bytes &&
    state.received == root_bytes &&
    state.used == 0
  if state.bits != 0 {
    sink_byte(output, state.pending.to_byte())
  }
  let adler = (state.s2.reinterpret_as_uint() << 16) |
    state.s1.reinterpret_as_uint()
  for i = 3; i >= 0; i = i - 1 {
    sink_byte(output, ((adler >> (i * 8)) & 255U).to_byte())
  }
  let length = output.offset - stream_at
  // Flush the placeholder before the positional backpatch, including tiny chunks.
  sink_flush(output)
  let patch : SinkCursor = {
    buffer: FixedArray::make(smaller(chunk, 4), b'\x00'),
    limit: tag_at + 8,
    offset: tag_at + 4,
    used: 0,
    node: 0,
    consume: (offset, buffer, count) => {
      sink_write_all(sink, offset, buffer, 0, count)
    },
  }
  sink_u32(patch, length.reinterpret_as_uint())
  sink_flush(patch)
}
