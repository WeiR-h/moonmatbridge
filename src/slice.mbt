///|
fn remap_array(
  source : NumericArray,
  shape : Array[Int],
  source_index : (Int) -> Int,
  limits : Limits,
) -> NumericArray raise MatError {
  let count = element_count(shape, limits, 0)
  let width = source.dtype.width()
  if count * width > limits.max_file_bytes / (if source.is_complex() { 2 } else { 1 }) {
    fail("file-limit", 0, "Transformed payload exceeds byte limit")
  }
  let copy_plane = fn(bytes : Bytes) {
    let out = Array::make(count * width, b'\x00')
    for i = 0; i < count; i = i + 1 {
      let index = source_index(i)
      for j = 0; j < width; j = j + 1 {
        out[i * width + j] = bytes[index * width + j]
      }
    }
    Bytes::from_array(out)
  }
  { name: source.name, dtype: source.dtype, shape: shape.copy(), real: copy_plane(source.real), imag: source.imag.map(copy_plane), is_global: source.is_global }
}

///|
/// Zero-based strided slicing. Counts are output dimensions; positive steps retain raw bits.
pub fn NumericArray::slice(
  self : NumericArray,
  starts : Array[Int],
  counts : Array[Int],
  steps? : Array[Int],
  limits? : Limits = default_limits(),
) -> NumericArray raise MatError {
  validate_limits(limits)
  let input_count = validate_array(self, limits)
  let rank = self.shape.length()
  let steps = steps.unwrap_or(Array::make(rank, 1))
  if starts.length() != rank || counts.length() != rank || steps.length() != rank {
    fail("invalid-slice", 0, "Slice vectors must have array rank")
  }
  for axis = 0; axis < rank; axis = axis + 1 {
    let size = self.shape[axis]
    if starts[axis] < 0 || starts[axis] > size || counts[axis] < 0 || steps[axis] <= 0 {
      fail("invalid-slice", axis, "Slice needs bounded starts, nonnegative counts and positive steps")
    }
    if counts[axis] > 0 && (starts[axis] == size || counts[axis] - 1 > (size - 1 - starts[axis]) / steps[axis]) {
      fail("invalid-slice", axis, "Last selected coordinate exceeds dimension")
    }
  }
  let strides = Array::make(rank, 1)
  if input_count != 0 {
    for axis = 1; axis < rank; axis = axis + 1 {
      strides[axis] = strides[axis - 1] * self.shape[axis - 1]
    }
  }
  remap_array(self, counts, fn(index) {
    let mut remainder = index
    let mut from = 0
    for axis = 0; axis < rank; axis = axis + 1 {
      from = from + (starts[axis] + remainder % counts[axis] * steps[axis]) * strides[axis]
      remainder = remainder / counts[axis]
    }
    from
  }, limits)
}

///|
/// Gather one axis in caller-specified order, including repeated indices, without numeric conversion.
pub fn NumericArray::gather_axis(
  self : NumericArray,
  axis : Int,
  indices : Array[Int],
  limits? : Limits = default_limits(),
) -> NumericArray raise MatError {
  validate_limits(limits)
  let input_count = validate_array(self, limits)
  if axis < 0 || axis >= self.shape.length() {
    fail("invalid-axis", axis, "Gather axis is outside array rank")
  }
  if indices.length() > limits.max_elements {
    fail("element-limit", axis, "Gather index count exceeds max_elements")
  }
  for index in indices {
    if index < 0 || index >= self.shape[axis] {
      fail("index-range", axis, "Gather coordinate is outside dimension")
    }
  }
  let shape = self.shape.copy()
  shape[axis] = indices.length()
  let mut stride = 1
  if input_count != 0 {
    for k = 0; k < axis; k = k + 1 {
      stride = stride * self.shape[k]
    }
  }
  remap_array(self, shape, fn(index) {
    let block = index / stride
    let before = index % stride
    let chosen = indices[block % indices.length()]
    before + stride * (chosen + self.shape[axis] * (block / indices.length()))
  }, limits)
}
