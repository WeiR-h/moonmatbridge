///|
pub fn tree_close_json(report : @mat.TreeCloseDifference) -> Json {
  let base = tree_diff_json({
    content_equal: report.within_tolerance,
    variable_order_changed: report.variable_order_changed,
    differences: report.differences,
    samples: report.samples,
    truncated: report.truncated,
  })
  let map = match base {
    Object(m) => m
    _ => Map([])
  }
  map["schema"] = "moonmatbridge/tree-close/1"
  map.remove("content_equal")
  map["exact_equal"] = Json::boolean(report.exact_equal)
  map["within_tolerance"] = Json::boolean(report.within_tolerance)
  map["atol"] = Json::number(report.atol)
  map["rtol"] = Json::number(report.rtol)
  map["equal_nan"] = Json::boolean(report.equal_nan)
  Json::object(map)
}

///|
/// Strict options parsing is shared by both CLI hosts and the JS export.
#warnings("-deprecated")
pub fn compare_tree_text(
  left : @mat.MatTree,
  right : @mat.MatTree,
  options : String,
) -> @mat.TreeCloseDifference raise @mat.MatError {
  if options.length() > 8192 {
    invalid("Tolerance options exceed 8192 characters")
  }
  let value = @json.parse(options[:], max_nesting_depth=4) catch {
    _ => {
      invalid("Invalid tolerance options JSON")
      Json::null()
    }
  }
  let map = object(value)
  reject_unknown(map, ["atol", "rtol", "equal_nan", "max_samples"])
  let number = fn(
    key : String,
    default_value : Double,
  ) -> Double raise @mat.MatError {
    match map.get(key) {
      None => default_value
      Some(Number(n, ..)) => n
      _ => {
        invalid("Expected numeric option: " + key)
        0.0
      }
    }
  }
  let equal_nan = match map.get("equal_nan") {
    None | Some(False) => false
    Some(True) => true
    _ => {
      invalid("equal_nan must be boolean")
      false
    }
  }
  let maximum = number("max_samples", 16.0)
  if maximum.is_inf() ||
    maximum.is_nan() ||
    maximum < 0.0 ||
    maximum > 256.0 ||
    maximum.to_int().to_double() != maximum {
    invalid("max_samples must be an integer between 0 and 256")
  }
  @mat.compare_trees_close(
    left,
    right,
    atol=number("atol", 0.0),
    rtol=number("rtol", 0.0),
    equal_nan~,
    max_samples=maximum.to_int(),
  )
}
