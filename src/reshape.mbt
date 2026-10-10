///|
/// Reshape in column-major order without converting or copying immutable payload bytes.
pub fn NumericArray::reshape(
  self : NumericArray,
  shape : Array[Int],
  limits? : Limits = default_limits(),
) -> NumericArray raise MatError {
  validate_limits(limits)
  let count = validate_array(self, limits)
  if element_count(shape, limits, 0) != count {
    fail("shape-mismatch", 0, "Reshape must preserve element count")
  }
  {
    name: self.name,
    dtype: self.dtype,
    shape: shape.copy(),
    real: self.real,
    imag: self.imag,
    is_global: self.is_global,
  }
}
