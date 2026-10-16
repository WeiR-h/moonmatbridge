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

///|
fn node_info(node : @mat.MatNode) -> Json {
  match node {
    Numeric(a) => {
      let doc : @mat.MatDocument = {
        description: "",
        little_endian: true,
        variables: [Dense(a)],
      }
      match document_info(doc) {
        { "arrays": [item], .. } => item
        _ => Json::null()
      }
    }
    Csc(a) => {
      let doc : @mat.MatDocument = {
        description: "",
        little_endian: true,
        variables: [Sparse(a)],
      }
      match document_info(doc) {
        { "arrays": [item], .. } => item
        _ => Json::null()
      }
    }
    Character(a) =>
      {
        "name": a.name,
        "storage": "char",
        "shape": Json::array(a.shape.map(n => Json::number(n.to_double()))),
        "encoding": a.encoding.name(),
        "bytes": a.data.length(),
        "global": a.is_global,
      }
    Cell(a) =>
      {
        "name": a.name,
        "storage": "cell",
        "shape": Json::array(a.shape.map(n => Json::number(n.to_double()))),
        "global": a.is_global,
        "children": Json::array(a.values.map(node_info)),
      }
    Structure(a) =>
      {
        "name": a.name,
        "storage": if a.class_name is Some(_) {
          "object"
        } else {
          "struct"
        },
        "shape": Json::array(a.shape.map(n => Json::number(n.to_double()))),
        "global": a.is_global,
        "fields": Json::array(a.fields.map(s => Json::string(s))),
        "class_name": match a.class_name {
          Some(s) => Json::string(s)
          None => Json::null()
        },
        "children": Json::array(a.values.map(node_info)),
      }
  }
}

///|
/// Recursive metadata preserves field order and column-major cell/struct child order.
pub fn tree_info(file : @mat.MatTree) -> Json {
  {
    "status": "ok",
    "version": @mat.version(),
    "format": "MAT Level 5",
    "source_endian": if file.little_endian {
      "little"
    } else {
      "big"
    },
    "arrays": Json::array(file.variables.map(node_info)),
  }
}
