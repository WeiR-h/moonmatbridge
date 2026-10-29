///|
fn captured_sink_tree(
  nodes : Array[MatNode],
  chunk : Int32,
  short : Int32,
  name_encoding~ : NameEncoding = Utf8,
) -> Bytes raise {
  let expected = write_tree(nodes, name_encoding~)
  let out = FixedArray::make(expected.length(), b'\x00')
  let calls = [0, 0]
  let sink : MatSink = {
    write_from: fn(offset, buffer, start, count) {
      if offset < 0 || count < 1 || offset > out.length() - count {
        return -1
      }
      calls[0] = calls[0] + 1
      if count > calls[1] {
        calls[1] = count
      }
      let n = if count < short { count } else { short }
      for i = 0; i < n; i = i + 1 {
        out[offset + i] = buffer[start + i]
      }
      n
    },
  }
  let size = write_tree_to(
    nodes,
    sink,
    limits={ ..default_write_limits(), chunk_bytes: chunk, },
    name_encoding~,
  )
  assert_eq(size, expected.length())
  assert_true(calls[0] > 0 && calls[1] <= chunk)
  let result = finish_owned_buffer(out)
  assert_true(result == expected)
  result
}

///|
test "sink mixed trees match fixed bytes at odd blocks and short writes" {
  for chunk in [1, 3, 7, 31, 63, 1048576] {
    for short in [1, 2, 19, 1048576] {
      let bytes = captured_sink_tree(mixed_tree(), chunk, short)
      assert_eq(read_tree(bytes).variables.length(), 2)
    }
  }
}

///|
test "sink empty file and empty recursive arrays retain canonical storage" {
  ignore(captured_sink_tree([], 3, 2))
  let nodes : Array[MatNode] = [
    Cell({ name: "empty", shape: [0, 3, 2], values: [], is_global: true, }),
    Structure({
      name: "record",
      shape: [0, 1],
      fields: ["a", "b"],
      values: [],
      class_name: None,
      is_global: false,
    }),
  ]
  ignore(captured_sink_tree(nodes, 5, 3))
}

///|
test "sink preserves all numeric classes and complex IEEE bytes" {
  let nodes : Array[MatNode] = []
  for
    dtype in [
      Float64,
      Float32,
      Int8,
      UInt8,
      Int16,
      UInt16,
      Int32,
      UInt32,
      Int64,
      UInt64,
      Logical,
    ] {
    let value : Value = match dtype {
      Float64 | Float32 => Floating(-0.0)
      Int8 | Int16 | Int32 | Int64 => Signed(-1L)
      UInt8 | UInt16 | UInt32 | UInt64 => Unsigned(1UL)
      Logical => Boolean(true)
    }
    nodes.push(
      Numeric(
        numeric_array(
          dtype.name(),
          dtype,
          [1, 2],
          [value, value],
          is_global=true,
        ),
      ),
    )
  }
  let raw = b"\x01\x00\x00\x00\x00\x00\xf8\x7f\x00\x00\x00\x00\x00\x00\x00\x80"
  nodes.push(Numeric(raw_array("complex", Float64, [1, 2], raw, imag=raw)))
  ignore(captured_sink_tree(nodes, 11, 4))
}

///|
test "sink retains noncanonical CSC active slots capacity and unused bytes" {
  let data = numeric_array("data", Float64, [4, 1], [
    Floating(1.0),
    Floating(-0.0),
    Floating(2.0),
    Floating(0.0),
  ])
  let sparse = raw_sparse_array(
    "sparse",
    Float64,
    [3, 1],
    [2, 0, 2, -77],
    [0, 3],
    data.real,
    nzmax=4,
  )
  ignore(captured_sink_tree([Csc(sparse)], 7, 3))
}

///|
test "sink applies explicit name encoding to fields and legacy class names" {
  let value = numeric_array("temporary", UInt64, [1, 1], [
    Unsigned(18446744073709551615UL),
  ])
  let number = { ..value, name: "", }
  let node : MatNode = Structure({
    name: "résultat",
    shape: [1, 1],
    fields: ["donnée"],
    values: [Numeric(number)],
    class_name: Some("Café"),
    is_global: true,
  })
  for encoding in [NameEncoding::Utf8, Latin1] {
    ignore(captured_sink_tree([node], 3, 2, name_encoding=encoding))
  }
}

///|
test "sink rejects invalid late roots before the first callback" {
  let a = numeric_array("a", Float64, [1, 1], [Floating(1.0)])
  let calls = [0]
  let sink : MatSink = {
    write_from: fn(_, _, _, count) {
      calls[0] = calls[0] + 1
      count
    },
  }
  let invalid = Numeric({ ..a, name: "bad", shape: [1, 2], })
  let code = try {
    ignore(write_tree_to([Numeric(a), invalid], sink))
    "accepted"
  } catch {
    e => e.code()
  }
  assert_eq(code, "payload-size")
  assert_eq(calls[0], 0)
  let duplicate = try {
    ignore(write_tree_to([Numeric(a), Numeric(a)], sink))
    "accepted"
  } catch {
    e => e.code()
  }
  assert_eq(duplicate, "duplicate-name")
  assert_eq(calls[0], 0)
}

///|
test "sink preflight enforces output metadata element and structural quotas" {
  let nodes = mixed_tree()
  let size = write_tree(nodes).length()
  let calls = [0]
  let sink : MatSink = {
    write_from: fn(_, _, _, count) {
      calls[0] = calls[0] + 1
      count
    },
  }
  let code = try {
    ignore(
      write_tree_to(nodes, sink, limits={
        ..default_write_limits(),
        max_output_bytes: size - 1,
      }),
    )
    "accepted"
  } catch {
    e => e.code()
  }
  assert_eq(code, "file-limit")
  let meta = try {
    ignore(
      write_tree_to(nodes, sink, limits={
        ..default_write_limits(),
        max_metadata_bytes: 0,
      }),
    )
    "accepted"
  } catch {
    e => e.code()
  }
  assert_eq(meta, "metadata-limit")
  let depth = try {
    ignore(
      write_tree_to(nodes, sink, tree_limits={
        ..default_tree_limits(),
        max_depth: 1,
      }),
    )
    "accepted"
  } catch {
    e => e.code()
  }
  assert_eq(depth, "depth-limit")
  assert_eq(calls[0], 0)
}

///|
test "sink rejects zero negative and oversized write counts" {
  for mode in [0, 1, 2] {
    let sink : MatSink = {
      write_from: fn(_, _, _, count) {
        if mode == 0 {
          0
        } else if mode == 1 {
          -1
        } else {
          count + 1
        }
      },
    }
    let code = try {
      ignore(write_tree_to(mixed_tree(), sink))
      "accepted"
    } catch {
      e => e.code()
    }
    assert_eq(code, "io-error")
  }
}

///|
test "sink invalid block sizes fail before output" {
  let calls = [0]
  let sink : MatSink = {
    write_from: fn(_, _, _, count) {
      calls[0] = calls[0] + 1
      count
    },
  }
  for chunk in [0, 8388609] {
    let code = try {
      ignore(
        write_tree_to([], sink, limits={
          ..default_write_limits(),
          chunk_bytes: chunk,
        }),
      )
      "accepted"
    } catch {
      e => e.code()
    }
    assert_eq(code, "invalid-limits")
  }
  assert_eq(calls[0], 0)
}
