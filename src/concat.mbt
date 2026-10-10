///|
/// Concatenate compatible arrays along one axis. Every plane is copied as canonical raw bytes.
pub fn concat_arrays(
  name : String,
  arrays : Array[NumericArray],
  axis : Int,
  limits? : Limits = default_limits(),
) -> NumericArray raise MatError {
  validate_limits(limits)
  validate_name(name, limits)
  if arrays.is_empty() || arrays.length() > limits.max_variables {
    fail("invalid-concat", 0, "Concat needs 1 to max_variables input arrays")
  }
  let first = arrays[0]
  ignore(validate_array(first, limits))
  if axis < 0 || axis >= first.shape.length() {
    fail("invalid-axis", axis, "Concat axis is outside array rank")
  }
  let shape = first.shape.copy()
  shape[axis] = 0
  for item in arrays {
    ignore(validate_array(item, limits))
    if item.dtype != first.dtype ||
      item.is_complex() != first.is_complex() ||
      item.is_global != first.is_global ||
      item.shape.length() != shape.length() {
      fail(
        "incompatible-array", 0, "Concat inputs need identical type, rank, complex and global flags",
      )
    }
    for k = 0; k < shape.length(); k = k + 1 {
      if k != axis && item.shape[k] != shape[k] {
        fail("shape-mismatch", k, "Non-concatenated dimensions must agree")
      }
    }
    if item.shape[axis] > 2147483647 - shape[axis] {
      fail("element-limit", axis, "Concatenated dimension overflows")
    }
    shape[axis] = shape[axis] + item.shape[axis]
  }
  let count = element_count(shape, limits, 0)
  let width = first.dtype.width()
  if count * width >
    limits.max_file_bytes / (if first.is_complex() { 2 } else { 1 }) {
    fail("file-limit", 0, "Concatenated payload exceeds byte limit")
  }
  let copy_plane = fn(imaginary : Bool) {
    let out = Array::make(count * width, b'\x00')
    if count > 0 {
      let mut stride = 1
      for k = 0; k < axis; k = k + 1 {
        stride = stride * shape[k]
      }
      let block = stride * shape[axis]
      for outer = 0; outer < count / block; outer = outer + 1 {
        let mut cursor = outer * block * width
        for item in arrays {
          let source = if imaginary { item.imag.unwrap() } else { item.real }
          let size = stride * item.shape[axis] * width
          for j = 0; j < size; j = j + 1 {
            out[cursor + j] = source[outer * size + j]
          }
          cursor = cursor + size
        }
      }
    }
    Bytes::from_array(out)
  }
  {
    name,
    dtype: first.dtype,
    shape,
    real: copy_plane(false),
    imag: if first.is_complex() {
      Some(copy_plane(true))
    } else {
      None
    },
    is_global: first.is_global,
  }
}
