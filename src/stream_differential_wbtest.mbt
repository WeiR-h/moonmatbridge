///|
fn mutation_accepts(bytes : Bytes, streamed : Bool) -> Bool {
  try {
    if streamed {
      ignore(
        read_selected_from(test_source(bytes, 3), [], limits={
          ..default_source_limits(),
          chunk_bytes: 7,
        }),
      )
    } else {
      ignore(read_selected(bytes, []))
    }
    true
  } catch {
    _ => false
  }
}

///|
test "fixed seed structural mutations agree across memory and short read sources" {
  for compressed in [false, true] {
    let bytes = write_tree(mixed_tree(), compressed~)
    let mut seed = 0x5a17U
    for i = 0; i < 256; i = i + 1 {
      seed = seed * 1664525U + 1013904223U
      let position = (seed % bytes.length().reinterpret_as_uint()).reinterpret_as_int()
      seed = seed * 1664525U + 1013904223U
      let mask = ((seed >> 24) | 1U).to_byte()
      let changed = Bytes::makei(bytes.length(), j => {
        if j == position {
          bytes[j] ^ mask
        } else {
          bytes[j]
        }
      })
      assert_eq(
        mutation_accepts(changed, false),
        mutation_accepts(changed, true),
      )
      if i % 8 == 0 {
        let truncated = bytes[0:position].to_owned()
        assert_eq(
          mutation_accepts(truncated, false),
          mutation_accepts(truncated, true),
        )
      }
    }
  }
}
