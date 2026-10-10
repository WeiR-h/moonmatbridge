///|
pub(all) struct DifferenceSample {
  plane : String
  index : Int
  coordinates : Array[Int]
  before : Bytes
  after : Bytes
} derive(@debug.Debug)

///|
pub extend DifferenceSample with @debug.Debug::{to_repr}

///|
pub(all) struct VariableDifference {
  name : String
  status : String
  metadata : Array[String]
  real_differences : Int
  imag_differences : Int
  samples : Array[DifferenceSample]
  truncated : Bool
} derive(@debug.Debug)

///|
pub extend VariableDifference with @debug.Debug::{to_repr}

///|
pub(all) struct DocumentDifference {
  content_equal : Bool
  variable_order_changed : Bool
  changed_variables : Int
  variables : Array[VariableDifference]
} derive(@debug.Debug)

///|
pub extend DocumentDifference with @debug.Debug::{to_repr}

///|
fn variable_planes(item : MatVariable) -> (DType, Array[Int], Bytes, Bytes?, Bool) {
  match item {
    Dense(a) => (a.dtype, a.shape, a.real, a.imag, a.is_global)
    Sparse(a) => (a.dtype, a.shape, a.real, a.imag, a.is_global)
  }
}

///|
fn difference_coordinates(item : MatVariable, index : Int) -> Array[Int] {
  match item {
    Dense(a) => {
      let mut remainder = index
      a.shape.map(fn(size) { let coordinate = remainder % size; remainder = remainder / size; coordinate })
    }
    Sparse(a) => {
      if index >= a.nnz() { return [] }
      let mut low = 0
      let mut high = a.shape[1] - 1
      while low < high {
        let middle = (low + high) / 2
        if a.col_ptrs[middle + 1] <= index { low = middle + 1 } else { high = middle }
      }
      [a.row_indices[index], low]
    }
  }
}

///|
fn compare_plane(
  before : Bytes,
  after : Bytes,
  width : Int,
  plane : String,
  item : MatVariable,
  samples : Array[DifferenceSample],
  maximum : Int,
) -> Int {
  let mut count = 0
  for index = 0; index < before.length() / width; index = index + 1 {
    let mut different = false
    for j = 0; j < width; j = j + 1 {
      if before[index * width + j] != after[index * width + j] { different = true }
    }
    if different {
      count = count + 1
      if samples.length() < maximum {
        samples.push({ plane, index, coordinates: difference_coordinates(item, index), before: before[index * width:(index + 1) * width].to_owned(), after: after[index * width:(index + 1) * width].to_owned() })
      }
    }
  }
  count
}

///|
fn compare_variable(left : MatVariable, right : MatVariable, maximum : Int) -> VariableDifference {
  let (ld, ls, lr, li, lg) = variable_planes(left)
  let (rd, rs, rr, ri, rg) = variable_planes(right)
  let metadata = []
  if ld != rd { metadata.push("dtype") }
  if ls != rs { metadata.push("shape") }
  if lg != rg { metadata.push("global") }
  if (li is Some(_)) != (ri is Some(_)) { metadata.push("complex") }
  let mut comparable = ld == rd && ls == rs && lr.length() == rr.length()
  match (left, right) {
    (Sparse(a), Sparse(b)) => {
      if a.nzmax != b.nzmax { metadata.push("nzmax") }
      if a.row_indices != b.row_indices { metadata.push("row_indices"); comparable = false }
      if a.col_ptrs != b.col_ptrs { metadata.push("col_ptrs"); comparable = false }
      if a.row_indices.length() != b.row_indices.length() { metadata.push("stored_slots") }
    }
    (Dense(_), Dense(_)) => ()
    _ => { metadata.push("storage"); comparable = false }
  }
  let samples = []
  let real_differences = if comparable { compare_plane(lr, rr, ld.width(), "real", left, samples, maximum) } else { 0 }
  let imag_differences = match (li, ri) {
    (Some(a), Some(b)) => if comparable && a.length() == b.length() { compare_plane(a, b, ld.width(), "imag", left, samples, maximum) } else { 0 }
    _ => 0
  }
  let changed = !metadata.is_empty() || real_differences != 0 || imag_differences != 0
  { name: left.name(), status: if changed { "changed" } else { "equal" }, metadata, real_differences, imag_differences, samples, truncated: real_differences + imag_differences > samples.length() }
}

///|
/// Match by variable name, compare canonical bits and metadata, and ignore original header/compression/endian.
/// Sample budget is global across the report. All comparable slots are still counted, including unused CSC capacity.
pub fn compare_documents(
  left : MatDocument,
  right : MatDocument,
  max_samples? : Int = 16,
  limits? : Limits = default_limits(),
) -> DocumentDifference raise MatError {
  validate_document(left.variables, limits~)
  validate_document(right.variables, limits~)
  if max_samples < 0 || max_samples > 256 { fail("invalid-limits", 0, "Diff sample budget must be between 0 and 256") }
  let right_by_name : Map[String, MatVariable] = Map([])
  for item in right.variables { right_by_name[item.name()] = item }
  let seen : Map[String, Bool] = Map([])
  let out = []
  let mut used_samples = 0
  let mut changed = 0
  for item in left.variables {
    seen[item.name()] = true
    let difference = match right_by_name.get(item.name()) {
      Some(other) => compare_variable(item, other, max_samples - used_samples)
      None => { name: item.name(), status: "removed", metadata: ["variable"], real_differences: 0, imag_differences: 0, samples: [], truncated: false }
    }
    if difference.status != "equal" { changed = changed + 1 }
    used_samples = used_samples + difference.samples.length()
    out.push(difference)
  }
  for item in right.variables {
    if !seen.contains(item.name()) {
      changed = changed + 1
      out.push({ name: item.name(), status: "added", metadata: ["variable"], real_differences: 0, imag_differences: 0, samples: [], truncated: false })
    }
  }
  { content_equal: changed == 0, variable_order_changed: left.variables.map(a => a.name()) != right.variables.map(a => a.name()), changed_variables: changed, variables: out }
}
