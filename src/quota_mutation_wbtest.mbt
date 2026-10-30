///|
fn quota_mutation_accepts(
  bytes : Bytes,
  streamed : Bool,
  mode : Int32,
  limits : Limits,
  tree : TreeLimits,
  chunk : Int32,
) -> Bool {
  try {
    if streamed {
      let source = test_source(bytes, 3)
      let configured : SourceLimits = {
        max_source_bytes: limits.max_file_bytes,
        max_expanded_bytes: limits.max_expanded_bytes,
        max_result_bytes: 8192,
        max_buffered_root_bytes: 8192,
        max_metadata_bytes: 8192,
        max_elements: limits.max_elements,
        max_variables: limits.max_variables,
        max_dimensions: limits.max_dimensions,
        max_name_bytes: limits.max_name_bytes,
        chunk_bytes: chunk,
      }
      match mode {
        0 => ignore(read_tree_from(source, limits=configured, tree_limits=tree))
        1 =>
          ignore(
            read_selected_from(source, [], limits=configured, tree_limits=tree),
          )
        _ =>
          ignore(
            inspect_roots_from(source, limits=configured, tree_limits=tree),
          )
      }
    } else {
      match mode {
        0 => ignore(read_tree(bytes, limits~, tree_limits=tree))
        1 => ignore(read_selected(bytes, [], limits~, tree_limits=tree))
        _ => ignore(inspect_roots(bytes, limits~, tree_limits=tree))
      }
    }
    true
  } catch {
    _ => false
  }
}

///|
test "fixed seed nested mutations and combined quotas agree across all read entry points" {
  for compressed in [false, true] {
    let original = write_tree(mixed_tree(), compressed~)
    let mut seed = 0x731ac5U
    for i = 0; i < 64; i = i + 1 {
      seed = seed * 1664525U + 1013904223U
      let position = (seed % original.length().reinterpret_as_uint()).reinterpret_as_int()
      seed = seed * 1664525U + 1013904223U
      let mask = ((seed >> 24) | 1U).to_byte()
      let bytes = match i % 3 {
        0 => original
        1 =>
          Bytes::makei(original.length(), j => {
            if j == position {
              original[j] ^ mask
            } else {
              original[j]
            }
          })
        _ => original[0:position].to_owned()
      }
      let limits : Limits = {
        max_file_bytes: 8192,
        max_expanded_bytes: if i % 4 == 0 {
          128
        } else {
          8192
        },
        max_elements: if i % 5 == 0 {
          1
        } else {
          1024
        },
        max_variables: if i % 7 == 0 {
          1
        } else {
          4
        },
        max_dimensions: if i % 11 == 0 {
          2
        } else {
          8
        },
        max_name_bytes: if i % 13 == 0 {
          1
        } else {
          1024
        },
      }
      let tree : TreeLimits = {
        max_depth: if i % 5 == 0 {
          1
        } else {
          64
        },
        max_nodes: if i % 7 == 0 {
          2
        } else {
          65536
        },
        max_fields: if i % 11 == 0 {
          1
        } else {
          4096
        },
      }
      let canonical = quota_mutation_accepts(bytes, false, 0, limits, tree, 7)
      for mode in [0, 1, 2] {
        let memory = quota_mutation_accepts(bytes, false, mode, limits, tree, 7)
        let source = quota_mutation_accepts(
          bytes,
          true,
          mode,
          limits,
          tree,
          1 + i % 7 * 2,
        )
        assert_eq([i, mode, if memory { 1 } else { 0 }], [
          i,
          mode,
          if canonical {
            1
          } else {
            0
          },
        ])
        assert_eq([i, mode, if source { 1 } else { 0 }], [
          i,
          mode,
          if canonical {
            1
          } else {
            0
          },
        ])
      }
    }
  }
}
