///|
/// Unambiguous, zero-based paths. Field punctuation is data, never path syntax.
pub(all) enum TreePathSegment {
  Root(String)
  CellElement(Int)
  StructElement(Int)
  Field(String)
} derive(Eq, @debug.Debug)

///|
pub extend TreePathSegment with Eq::{equal, not_equal}

///|
pub extend TreePathSegment with @debug.Debug::{to_repr}

///|
pub(all) struct TreeDifferenceSample {
  path : Array[TreePathSegment]
  kind : String
  index : Int
  coordinates : Array[Int]
  before : Bytes
  after : Bytes
} derive(@debug.Debug)

///|
pub extend TreeDifferenceSample with @debug.Debug::{to_repr}

///|
pub(all) struct TreeDifference {
  content_equal : Bool
  variable_order_changed : Bool
  differences : Int
  samples : Array[TreeDifferenceSample]
  truncated : Bool
} derive(@debug.Debug)

///|
pub extend TreeDifference with @debug.Debug::{to_repr}

///|
priv struct TreeDiffState {
  tolerance : TreeTolerance?
  mut exact_count : Int
  maximum : Int
  mut count : Int
  samples : Array[TreeDifferenceSample]
}

///|
fn TreeDiffState::add(
  self : TreeDiffState,
  path : Array[TreePathSegment],
  kind : String,
  index? : Int = -1,
  coordinates? : Array[Int] = [],
  before? : Bytes = b"",
  after? : Bytes = b"",
  exact? : Bool = true,
) -> Unit {
  self.count = self.count + 1
  if exact {
    self.exact_count = self.exact_count + 1
  }
  if self.samples.length() < self.maximum {
    self.samples.push({
      path: path.copy(),
      kind,
      index,
      coordinates,
      before,
      after,
    })
  }
}

///|
fn tree_kind(node : MatNode) -> String {
  match node {
    Numeric(_) => "numeric"
    Csc(_) => "csc"
    Character(_) => "char"
    Cell(_) => "cell"
    Structure(a) => if a.class_name is Some(_) { "object" } else { "struct" }
  }
}

///|
fn node_global(node : MatNode) -> Bool {
  match node {
    Numeric(a) => a.is_global
    Csc(a) => a.is_global
    Character(a) => a.is_global
    Cell(a) => a.is_global
    Structure(a) => a.is_global
  }
}

///|
fn tree_coordinates(shape : Array[Int], index : Int) -> Array[Int] {
  let mut remainder = index
  if shape.contains(0) {
    return []
  }
  shape.map(fn(size) {
    let value = remainder % size
    remainder = remainder / size
    value
  })
}

///|
fn diff_tree_plane(
  state : TreeDiffState,
  path : Array[TreePathSegment],
  kind : String,
  left : Bytes,
  right : Bytes,
  width : Int,
  shape : Array[Int],
  floating? : DType,
) -> Unit {
  if left.length() != right.length() {
    state.add(path, kind + "_size")
  }
  let count = (if left.length() < right.length() {
      left.length()
    } else {
      right.length()
    }) /
    width
  for i = 0; i < count; i = i + 1 {
    let mut changed = false
    for j = 0; j < width; j = j + 1 {
      if left[i * width + j] != right[i * width + j] {
        changed = true
      }
    }
    let equivalent = match (state.tolerance, floating) {
      (Some(t), Some(dtype)) => tree_float_close(left, right, i, dtype, t)
      _ => !changed
    }
    if !equivalent {
      // Allocate coordinate/byte samples only inside the global sample budget.
      if state.samples.length() < state.maximum {
        state.add(
          path,
          kind,
          index=i,
          coordinates=tree_coordinates(shape, i),
          before=left[i * width:(i + 1) * width].to_owned(),
          after=right[i * width:(i + 1) * width].to_owned(),
          exact=changed,
        )
      } else {
        state.count = state.count + 1
        if changed {
          state.exact_count = state.exact_count + 1
        }
      }
    } else if changed {
      state.exact_count = state.exact_count + 1
    }
  }
}

///|
fn diff_tree_imag(
  state : TreeDiffState,
  path : Array[TreePathSegment],
  left : Bytes?,
  right : Bytes?,
  width : Int,
  shape : Array[Int],
  floating? : DType,
) -> Unit {
  match (left, right) {
    (Some(a), Some(b)) =>
      diff_tree_plane(state, path, "imag", a, b, width, shape, floating?)
    (None, None) => ()
    _ => state.add(path, "complex")
  }
}

///|
fn diff_tree_node(
  state : TreeDiffState,
  path : Array[TreePathSegment],
  left : MatNode,
  right : MatNode,
) -> Unit {
  if left.name() != right.name() {
    state.add(path, "name")
  }
  if left.shape() != right.shape() {
    state.add(path, "shape")
  }
  if node_global(left) != node_global(right) {
    state.add(path, "global")
  }
  if tree_kind(left) != tree_kind(right) {
    state.add(path, "type")
  }
  match (left, right) {
    (Numeric(a), Numeric(b)) =>
      if a.dtype != b.dtype {
        state.add(path, "dtype")
      } else {
        diff_tree_plane(
          state,
          path,
          "real",
          a.real,
          b.real,
          a.dtype.width(),
          a.shape,
          floating?=if a.dtype == Float64 || a.dtype == Float32 {
            Some(a.dtype)
          } else {
            None
          },
        )
        diff_tree_imag(
          state,
          path,
          a.imag,
          b.imag,
          a.dtype.width(),
          a.shape,
          floating?=if a.dtype == Float64 || a.dtype == Float32 {
            Some(a.dtype)
          } else {
            None
          },
        )
      }
    (Csc(a), Csc(b)) => {
      if a.dtype != b.dtype {
        state.add(path, "dtype")
      }
      if a.nzmax != b.nzmax {
        state.add(path, "nzmax")
      }
      if a.row_indices != b.row_indices {
        state.add(path, "row_indices")
      }
      if a.col_ptrs != b.col_ptrs {
        state.add(path, "col_ptrs")
      }
      if a.dtype == b.dtype {
        // CSC coordinates denote storage slots, including inactive capacity.
        diff_tree_plane(
          state,
          path,
          "real",
          a.real,
          b.real,
          a.dtype.width(),
          [],
          floating?=if a.dtype == Float64 { Some(Float64) } else { None },
        )
        diff_tree_imag(
          state,
          path,
          a.imag,
          b.imag,
          a.dtype.width(),
          [],
          floating?=if a.dtype == Float64 { Some(Float64) } else { None },
        )
      }
    }
    (Character(a), Character(b)) =>
      if a.encoding != b.encoding {
        state.add(path, "encoding")
      } else {
        diff_tree_plane(
          state,
          path,
          "char_units",
          a.data,
          b.data,
          a.encoding.width(),
          [],
        )
      }
    (Cell(a), Cell(b)) => {
      if a.values.length() != b.values.length() {
        state.add(path, "children")
      }
      let count = if a.values.length() < b.values.length() {
        a.values.length()
      } else {
        b.values.length()
      }
      for i = 0; i < count; i = i + 1 {
        diff_tree_node(state, path + [CellElement(i)], a.values[i], b.values[i])
      }
    }
    (Structure(a), Structure(b)) => {
      if a.class_name != b.class_name {
        state.add(path, "class_name")
      }
      if a.fields != b.fields {
        state.add(path, "field_order")
      }
      let fields : Map[String, Int] = Map([])
      let left_fields : Map[String, Bool] = Map([])
      for field in a.fields {
        left_fields[field] = true
      }
      for i = 0; i < b.fields.length(); i = i + 1 {
        fields[b.fields[i]] = i
      }
      let elements = if a.fields.is_empty() {
        0
      } else {
        a.values.length() / a.fields.length()
      }
      let others = if b.fields.is_empty() {
        0
      } else {
        b.values.length() / b.fields.length()
      }
      for field in a.fields {
        if !fields.contains(field) {
          state.add(path + [Field(field)], "removed")
        }
      }
      for field in b.fields {
        if !left_fields.contains(field) {
          state.add(path + [Field(field)], "added")
        }
      }
      let count = if elements < others { elements } else { others }
      for i = 0; i < count; i = i + 1 {
        for j = 0; j < a.fields.length(); j = j + 1 {
          if fields.get(a.fields[j]) is Some(k) {
            diff_tree_node(
              state,
              path + [StructElement(i), Field(a.fields[j])],
              a.values[i * a.fields.length() + j],
              b.values[i * b.fields.length() + k],
            )
          }
        }
      }
    }
    _ => ()
  }
}

///|
/// Exact recursive comparison; ignores MAT header, compression and source endian.
/// All input nodes are validated even when the sample budget is zero.
fn run_tree_comparison(
  left : MatTree,
  right : MatTree,
  tolerance : TreeTolerance?,
  max_samples? : Int = 16,
  limits? : Limits = default_limits(),
  tree_limits? : TreeLimits = default_tree_limits(),
) -> (TreeDiffState, Bool) raise MatError {
  validate_tree(left.variables, limits~, tree_limits~)
  validate_tree(right.variables, limits~, tree_limits~)
  if max_samples < 0 || max_samples > 256 {
    fail("invalid-limits", 0, "Diff sample budget must be between 0 and 256")
  }
  let state : TreeDiffState = {
    maximum: max_samples,
    count: 0,
    exact_count: 0,
    tolerance,
    samples: [],
  }
  let by_name : Map[String, MatNode] = Map([])
  for node in right.variables {
    by_name[node.name()] = node
  }
  let seen : Map[String, Bool] = Map([])
  let order = left.variables.map(MatNode::name) !=
    right.variables.map(MatNode::name)
  for node in left.variables {
    seen[node.name()] = true
    let path = [Root(node.name())]
    match by_name.get(node.name()) {
      Some(other) => diff_tree_node(state, path, node, other)
      None => state.add(path, "removed")
    }
  }
  for node in right.variables {
    if !seen.contains(node.name()) {
      state.add([Root(node.name())], "added")
    }
  }
  (state, order)
}

///|
pub fn compare_trees(
  left : MatTree,
  right : MatTree,
  max_samples? : Int = 16,
  limits? : Limits = default_limits(),
  tree_limits? : TreeLimits = default_tree_limits(),
) -> TreeDifference raise MatError {
  let (state, order) = run_tree_comparison(
    left,
    right,
    None,
    max_samples~,
    limits~,
    tree_limits~,
  )
  {
    content_equal: state.count == 0,
    variable_order_changed: order,
    differences: state.count,
    samples: state.samples,
    truncated: state.count > state.samples.length(),
  }
}
