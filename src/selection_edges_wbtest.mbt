///|
test "omitted nested names unsupported children valid conversions and root quotas remain enforced" {
  let good = Numeric(numeric_array("good", Float64, [1, 1], [Floating(1.0)]))
  let value = Numeric(numeric_array("integer", UInt64, [1, 1], [Unsigned(7UL)]))
  let bytes = write_tree([good, value])
  let second = tag(
    bytes,
    tag(bytes, 128, bytes.length(), true).next,
    bytes.length(),
    true,
  )
  let flags = tag(bytes, second.start, second.start + second.size, true)
  let dims = tag(bytes, flags.next, second.start + second.size, true)
  let name = tag(bytes, dims.next, second.start + second.size, true)
  let converted = changed(bytes, name.next, b'\x0c')
  assert_eq(read_selected(converted, ["good"]).variables.length(), 1)
  assert_eq(inspect_roots(converted)[1].class_id, 15)
  assert_eq(
    error_code(() => {
      ignore(
        inspect_roots(converted, limits={
          ..default_limits(),
          max_variables: 1,
        }),
      )
    }),
    "variable-limit",
  )
  let sparse = Csc(
    raw_sparse_array(
      "s",
      Float64,
      [3, 2],
      [0, 2],
      [0, 1, 2],
      Bytes::make(16, b'\x00'),
    ),
  )
  let nested = write_tree([
    good,
    Cell({ name: "outer", shape: [1, 1], values: [sparse], is_global: false, }),
  ])
  let root = tag(
    nested,
    tag(nested, 128, nested.length(), true).next,
    nested.length(),
    true,
  )
  let f = tag(nested, root.start, root.start + root.size, true)
  let d = tag(nested, f.next, root.start + root.size, true)
  let n = tag(nested, d.next, root.start + root.size, true)
  let child = tag(nested, n.next, root.start + root.size, true)
  let cf = tag(nested, child.start, child.start + child.size, true)
  let cd = tag(nested, cf.next, child.start + child.size, true)
  let cn = tag(nested, cd.next, child.start + child.size, true)
  let nul_name = changed(nested, cn.start, b'\x00')
  assert_eq(
    error_code(() => ignore(read_selected(nul_name, ["good"]))),
    "invalid-name",
  )
  assert_eq(error_code(() => ignore(inspect_roots(nul_name))), "invalid-name")
  let unsupported = changed(nested, cf.start, b'\x10')
  assert_eq(
    error_code(() => ignore(read_selected(unsupported, ["good"]))),
    "unsupported-class",
  )
}
