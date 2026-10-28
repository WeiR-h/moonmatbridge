///|
pub fn diff_json(report : @mat.DocumentDifference) -> Json {
  let entries = report.variables.map(fn(variable) {
    (
      {
        "name": variable.name,
        "status": variable.status,
        "metadata": Json::array(variable.metadata.map(Json::string)),
        "real_differences": variable.real_differences,
        "imag_differences": variable.imag_differences,
        "truncated": variable.truncated,
        "samples": Json::array(
          variable.samples.map(fn(sample) {
            (
              {
                "plane": sample.plane,
                "index": sample.index,
                "coordinates": Json::array(
                  sample.coordinates.map(n => Json::number(n.to_double())),
                ),
                "before_hex": hex(sample.before),
                "after_hex": hex(sample.after),
              } : Json)
          }),
        ),
      } : Json)
  })
  {
    "schema": "moonmatbridge/diff/1",
    "status": "ok",
    "version": @mat.version(),
    "comparison": "by-name-bit-exact",
    "content_equal": report.content_equal,
    "variable_order_changed": report.variable_order_changed,
    "changed_variables": report.changed_variables,
    "variables": Json::array(entries),
  }
}

///|
pub fn tree_diff_json(report : @mat.TreeDifference) -> Json {
  let samples = report.samples.map(fn(sample) {
    let path = sample.path.map(fn(segment) {
      match segment {
        Root(name) => ({ "kind": "root", "name": name } : Json)
        Field(name) => ({ "kind": "field", "name": name } : Json)
        CellElement(index) => ({ "kind": "cell", "index": index } : Json)
        StructElement(index) =>
          ({ "kind": "struct_element", "index": index } : Json)
      }
    })
    (
      {
        "path": Json::array(path),
        "kind": sample.kind,
        "index": sample.index,
        "coordinates": Json::array(
          sample.coordinates.map(n => Json::number(n.to_double())),
        ),
        "before_hex": hex(sample.before),
        "after_hex": hex(sample.after),
      } : Json)
  })
  {
    "schema": "moonmatbridge/tree-diff/1",
    "status": "ok",
    "content_equal": report.content_equal,
    "variable_order_changed": report.variable_order_changed,
    "differences": report.differences,
    "truncated": report.truncated,
    "coordinate_base": 0,
    "samples": Json::array(samples),
  }
}
