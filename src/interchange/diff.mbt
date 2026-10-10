///|
pub fn diff_json(report : @mat.DocumentDifference) -> Json {
  let entries = report.variables.map(fn(variable) {
    ({ "name": variable.name, "status": variable.status, "metadata": Json::array(variable.metadata.map(Json::string)),
      "real_differences": variable.real_differences, "imag_differences": variable.imag_differences, "truncated": variable.truncated,
      "samples": Json::array(variable.samples.map(fn(sample) {
        ({ "plane": sample.plane, "index": sample.index, "coordinates": Json::array(sample.coordinates.map(n => Json::number(n.to_double()))), "before_hex": hex(sample.before), "after_hex": hex(sample.after) } : Json)
      })) } : Json)
  })
  { "schema": "moonmatbridge/diff/1", "status": "ok", "version": @mat.version(), "comparison": "by-name-bit-exact", "content_equal": report.content_equal, "variable_order_changed": report.variable_order_changed, "changed_variables": report.changed_variables, "variables": Json::array(entries) }
}
