///|
/// JS arrays cross the ABI as FixedArray, independently of MoonBit Array layout.
/// The existing MoonBit functions keep their Array[String] signatures.
#export_name("select_mat")
pub fn export_select_mat(bytes : Bytes, names : FixedArray[String]) -> BinaryResult {
  select_mat(bytes, Array::from_fixed_array(names))
}

///|
#export_name("select_mat_with_options")
pub fn export_select_mat_with_options(
  bytes : Bytes,
  names : FixedArray[String],
  options : String,
) -> BinaryResult {
  select_mat_with_options(bytes, Array::from_fixed_array(names), options)
}

///|
#export_name("select_source_mat")
pub fn export_select_source_mat(
  source : @mat.MatSource,
  names : FixedArray[String],
) -> BinaryResult {
  select_source_mat(source, Array::from_fixed_array(names))
}

///|
#export_name("select_source_mat_with_options")
pub fn export_select_source_mat_with_options(
  source : @mat.MatSource,
  names : FixedArray[String],
  options : String,
) -> BinaryResult {
  select_source_mat_with_options(source, Array::from_fixed_array(names), options)
}

///|
#export_name("select_source_mat_to")
pub fn export_select_source_mat_to(
  source : @mat.MatSource,
  names : FixedArray[String],
  sink : @mat.MatSink,
) -> String {
  select_source_mat_to(source, Array::from_fixed_array(names), sink)
}

///|
#export_name("select_source_mat_to_with_options")
pub fn export_select_source_mat_to_with_options(
  source : @mat.MatSource,
  names : FixedArray[String],
  sink : @mat.MatSink,
  options : String,
) -> String {
  select_source_mat_to_with_options(
    source, Array::from_fixed_array(names), sink, options,
  )
}
