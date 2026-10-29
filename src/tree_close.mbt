///|
priv struct TreeTolerance {
  atol : Double
  rtol : Double
  equal_nan : Bool
}

///|
pub(all) struct TreeCloseDifference {
  exact_equal : Bool
  within_tolerance : Bool
  variable_order_changed : Bool
  differences : Int32
  samples : Array[TreeDifferenceSample]
  truncated : Bool
  atol : Double
  rtol : Double
  equal_nan : Bool
} derive(@debug.Debug)

///|
pub extend TreeCloseDifference with @debug.Debug::{to_repr}

///|
fn tree_abs(n : Double) -> Double {
  if n < 0.0 {
    -n
  } else {
    n
  }
}

///|
fn tree_float_close(
  left : Bytes,
  right : Bytes,
  index : Int32,
  dtype : DType,
  tolerance : TreeTolerance,
) -> Bool {
  let (a, b) = match
    (
      scalar_at(left, index * dtype.width(), dtype, true),
      scalar_at(right, index * dtype.width(), dtype, true),
    ) {
    (Floating(a), Floating(b)) => (a, b)
    _ => return false
  }
  if a.is_nan() || b.is_nan() {
    return tolerance.equal_nan && a.is_nan() && b.is_nan()
  }
  if a == b {
    return true
  }
  if a.is_inf() || b.is_inf() {
    return false
  }
  if tolerance.atol == 0.0 && tolerance.rtol == 0.0 {
    return false
  }
  let aa = tree_abs(a)
  let bb = tree_abs(b)
  let scale = if aa > bb { aa } else { bb }
  // Same-sign subtraction is finite. Opposite-sign extreme values are halved
  // before subtraction; the relative bound is then normalized without forming
  // either an overflowing difference or atol + rtol * scale.
  let half = (a < 0.0) != (b < 0.0) && scale > 8.988465674311579e307
  let delta = if half { tree_abs(a * 0.5 - b * 0.5) } else { tree_abs(a - b) }
  let absolute = if half { tolerance.atol * 0.5 } else { tolerance.atol }
  if delta <= absolute {
    return true
  }
  let relative = (delta - absolute) / scale
  (if half { relative * 2.0 } else { relative }) <= tolerance.rtol
}

///|
pub fn compare_trees_close(
  left : MatTree,
  right : MatTree,
  atol~ : Double = 0.0,
  rtol~ : Double = 0.0,
  equal_nan~ : Bool = false,
  max_samples~ : Int32 = 16,
  limits~ : Limits = default_limits(),
  tree_limits~ : TreeLimits = default_tree_limits(),
) -> TreeCloseDifference raise MatError {
  if atol.is_nan() ||
    atol.is_inf() ||
    atol < 0.0 ||
    rtol.is_nan() ||
    rtol.is_inf() ||
    rtol < 0.0 {
    fail("invalid-limits", 0, "Tolerance must be finite and nonnegative")
  }
  let (state, order) = run_tree_comparison(
    left,
    right,
    Some({ atol, rtol, equal_nan, }),
    max_samples~,
    limits~,
    tree_limits~,
  )
  if order {
    state.add([], "root_order")
  }
  {
    exact_equal: state.exact_count == 0,
    within_tolerance: state.count == 0,
    variable_order_changed: order,
    differences: state.count,
    samples: state.samples,
    truncated: state.count > state.samples.length(),
    atol,
    rtol,
    equal_nan,
  }
}
