///|
/// Mixed dense/CSC metadata. Large sparse shapes are reported without densifying.
pub fn document_info(file : @mat.MatDocument) -> Json {
  let entries = file.variables.map(fn(variable) {
    match variable {
      Dense(a) =>
        (
          {
            "name": a.name,
            "storage": "dense",
            "dtype": a.dtype.name(),
            "shape": Json::array(a.shape.map(n => Json::number(n.to_double()))),
            "elements": a.length(),
            "complex": a.is_complex(),
            "global": a.is_global,
          } : Json)
      Sparse(a) =>
        (
          {
            "name": a.name,
            "storage": "csc",
            "dtype": a.dtype.name(),
            "shape": Json::array(a.shape.map(n => Json::number(n.to_double()))),
            "elements": a.nnz(),
            "stored_slots": a.row_indices.length(),
            "nzmax": a.nzmax,
            "dense_elements": (a.shape[0].to_uint64() * a.shape[1].to_uint64()).to_string(),
            "complex": a.imag is Some(_),
            "global": a.is_global,
          } : Json)
    }
  })
  {
    "status": "ok",
    "version": @mat.version(),
    "format": "MAT Level 5",
    "source_endian": if file.little_endian {
      "little"
    } else {
      "big"
    },
    "arrays": Json::array(entries),
  }
}
