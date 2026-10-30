///|
test "bounded payload copy preserves sentinels across every eight-byte tail" {
  let bytes = Bytes::makei(48, i => ((i * 31 + 7) & 255).to_byte())
  for at in [0, 1, 7, 13] {
    for start in [0, 3] {
      for size = 0; size <= 32; size = size + 1 {
        let target = FixedArray::make(64, b'\xff')
        let cursor : SinkCursor = {
          buffer: target,
          consume: fn(_offset, _buffer, _count) { () },
          limit: 64,
          offset: at,
          used: at,
          node: 0,
        }
        sink_copy(cursor, bytes, start, size)
        assert_eq(cursor.used, at + size)
        for i = 0; i < 64; i = i + 1 {
          assert_eq(
            target[i],
            if i >= at && i < at + size {
              bytes[start + i - at]
            } else {
              b'\xff'
            },
          )
        }
      }
    }
  }
}
