///|
/// axes[k] identifies the source axis used for output axis k. Both planes retain raw bits.
pub fn NumericArray::permute_axes(
  self : NumericArray,
  axes : Array[Int],
  limits? : Limits = default_limits(),
) -> NumericArray raise MatError {
  validate_limits(limits)
  let count = validate_array(self, limits)
  let rank = self.shape.length()
  if axes.length() != rank {
    fail("invalid-axes", 0, "Axes must contain every dimension exactly once")
  }
  let seen = Array::make(rank, false)
  for axis in axes {
    if axis < 0 || axis >= rank || seen[axis] {
      fail("invalid-axes", 0, "Axes must contain every dimension exactly once")
    }
    seen[axis] = true
  }
  let shape = axes.map(fn(axis) { self.shape[axis] })
  if count == 0 {
    return {
      name: self.name,
      dtype: self.dtype,
      shape,
      real: self.real,
      imag: self.imag,
      is_global: self.is_global,
    }
  }
  let strides = Array::make(rank, 1)
  for k = 1; k < rank; k = k + 1 {
    strides[k] = strides[k - 1] * self.shape[k - 1]
  }
  let width = self.dtype.width()
  let remap = fn(bytes : Bytes) {
    let out = Array::make(bytes.length(), b'\x00')
    for index = 0; index < count; index = index + 1 {
      let mut remainder = index
      let mut source = 0
      for k = 0; k < rank; k = k + 1 {
        source = source + remainder % shape[k] * strides[axes[k]]
        remainder = remainder / shape[k]
      }
      for j = 0; j < width; j = j + 1 {
        out[index * width + j] = bytes[source * width + j]
      }
    }
    Bytes::from_array(out)
  }
  {
    name: self.name,
    dtype: self.dtype,
    shape,
    real: remap(self.real),
    imag: self.imag.map(remap),
    is_global: self.is_global,
  }
}
