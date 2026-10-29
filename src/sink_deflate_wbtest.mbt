///|
fn compressed_sink_capture(
  nodes : Array[MatNode],
  chunk : Int32,
  short : Int32,
) -> Bytes raise {
  let out : Array[Byte] = []
  let largest = [0]
  let sink : MatSink = {
    write_from: fn(offset, buffer, start, count) {
      if count > largest[0] {
        largest[0] = count
      }
      let n = smaller(short, count)
      while out.length() < offset + n {
        out.push(b'\x00')
      }
      for i = 0; i < n; i = i + 1 {
        out[offset + i] = buffer[start + i]
      }
      n
    },
  }
  let size = write_tree_to(nodes, sink, compressed=true, limits={
    ..default_write_limits(),
    chunk_bytes: chunk,
  })
  assert_eq(size, out.length())
  assert_true(largest[0] <= chunk)
  let bytes = Bytes::from_array(out)
  assert_true(write_tree(read_tree(bytes).variables) == write_tree(nodes))
  bytes
}

///|
test "compressed sink keeps root streams deterministic across chunks and short writes" {
  let nodes = mixed_tree()
  let expected = compressed_sink_capture(nodes, 1048576, 1048576)
  for chunk in [1, 3, 7, 17, 65535] {
    for short in [1, 5, 1000000] {
      assert_true(compressed_sink_capture(nodes, chunk, short) == expected)
    }
  }
}

///|
test "compressed sink spans fixed raw block boundaries with dictionary and stored fallback" {
  let buffer = FixedArray::make(524216, b'\x00')
  for i = 0; i < buffer.length(); i = i + 1 {
    buffer[i] = ((i * 31 + i / 251) % 256).to_byte()
  }
  let pattern = raw_array(
    "block",
    UInt8,
    [1, buffer.length()],
    finish_owned_buffer(buffer),
  )
  let small = numeric_array("small", Float64, [1, 1], [Floating(-0.0)])
  let nodes = [Numeric(pattern), Numeric(small)]
  let expected = compressed_sink_capture(nodes, 16381, 3)
  assert_true(compressed_sink_capture(nodes, 1048576, 1048576) == expected)
  assert_true(expected.length() < write_tree(nodes).length())
}

///|
test "compressed sink rejects backpatch failure and late invalid data" {
  let end = [0]
  let sink : MatSink = {
    write_from: fn(offset, _, _, count) {
      if offset < end[0] {
        -1
      } else {
        end[0] = offset + count
        count
      }
    },
  }
  let code = try {
    ignore(write_tree_to(mixed_tree(), sink, compressed=true))
    "accepted"
  } catch {
    e => e.code()
  }
  assert_eq(code, "io-error")
  assert_true(end[0] > 128)
  let a = numeric_array("late", UInt8, [1, 1], [Unsigned(1UL)])
  let calls = [0]
  let no_io : MatSink = {
    write_from: fn(_, _, _, count) {
      calls[0] = calls[0] + 1
      count
    },
  }
  let invalid = Numeric({ ..a, shape: [1, 2], })
  let rejected = try {
    ignore(write_tree_to([mixed_tree()[0], invalid], no_io, compressed=true))
    "accepted"
  } catch {
    e => e.code()
  }
  assert_eq(rejected, "payload-size")
  assert_eq(calls[0], 0)
}

///|
test "compressed sink empty variable set is canonical header only" {
  assert_true(compressed_sink_capture([], 1, 1) == write_tree([]))
}
