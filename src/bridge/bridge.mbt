///|
/// Binary results keep typed errors out of the host language ABI.
pub struct BinaryResult {
  priv data : Bytes
  priv error : String?
}

///|
fn binary(work : () -> Bytes raise @mat.MatError) -> BinaryResult {
  { data: work(), error: None, } catch {
    error => { data: b"", error: Some(@wire.error_json(error).stringify()), }
  }
}

///|
#export_name("result_status")
pub fn result_status(result : BinaryResult) -> String {
  match result.error {
    Some(error) => error
    None =>
      (
        {
          "status": "ok",
          "bytes": result.data.length(),
          "version": @mat.version(),
        } : Json).stringify()
  }
}

///|
#export_name("result_bytes")
pub fn result_bytes(result : BinaryResult) -> Bytes {
  result.data
}

///|
#export_name("inspect_mat")
pub fn inspect_mat(bytes : Bytes) -> String {
  @wire.tree_info(@mat.read_tree(bytes)).stringify() catch {
    error => @wire.error_json(error).stringify()
  }
}

///|
#export_name("inspect_roots")
pub fn inspect_roots(bytes : Bytes) -> String {
  @wire.roots_info(@mat.inspect_roots(bytes)).stringify() catch {
    error => @wire.error_json(error).stringify()
  }
}

///|
#export_name("mat_to_json")
pub fn mat_to_json(bytes : Bytes) -> String {
  @wire.to_json(@mat.read_mat(bytes).arrays).stringify() catch {
    error => @wire.error_json(error).stringify()
  }
}

///|
#export_name("json_to_mat")
pub fn json_to_mat(text : String) -> BinaryResult {
  binary(() => @mat.write_mat(@wire.from_json(text)))
}

///|
#export_name("roundtrip_mat")
pub fn roundtrip_mat(bytes : Bytes) -> BinaryResult {
  binary(() => @mat.write_tree(@mat.read_tree(bytes).variables))
}

///|
#export_name("mat_to_npy")
pub fn mat_to_npy(bytes : Bytes, name : String) -> BinaryResult {
  binary(() => {
    let file = @mat.read_document(bytes)
    match file.get(name) {
      Some(Dense(array)) => @mat.write_npy(array)
      Some(Sparse(_)) =>
        raise @mat.MatError(
          "explicit-densification-required", 0, "Use densify before exporting sparse data to NPY",
        )
      None =>
        raise @mat.MatError("missing-variable", 0, "No variable named: " + name)
    }
  })
}

///|
#export_name("sample_mat")
pub fn sample_mat() -> BinaryResult {
  binary(() => @mat.write_mat(@wire.sample()))
}

///|
#export_name("inflate_zlib")
pub fn inflate_zlib(bytes : Bytes, limit : Int) -> BinaryResult {
  binary(() => @mat.inflate_zlib(bytes, max_bytes=limit))
}

///|
#export_name("select_mat")
pub fn select_mat(bytes : Bytes, names : Array[String]) -> BinaryResult {
  binary(() => @mat.write_tree(@mat.read_selected(bytes, names).variables))
}

///|
#export_name("npy_to_mat")
pub fn npy_to_mat(bytes : Bytes, name : String) -> BinaryResult {
  binary(() => @mat.write_mat([@mat.read_npy(bytes, name)]))
}

///|
#export_name("transform_mat")
pub fn transform_mat(bytes : Bytes, plan : String) -> BinaryResult {
  binary(() => {
    @mat.write_document(
      @wire.transform_document(@mat.read_document(bytes).variables, plan),
    )
  })
}

///|
#export_name("compress_mat")
pub fn compress_mat(bytes : Bytes) -> BinaryResult {
  binary(() => @mat.write_tree(@mat.read_tree(bytes).variables, compressed=true))
}

///|
#export_name("deflate_zlib")
pub fn deflate_zlib(bytes : Bytes, limit : Int) -> BinaryResult {
  binary(() => @mat.deflate_zlib(bytes, max_bytes=limit))
}

///|
#export_name("convert_storage")
pub fn convert_storage(
  bytes : Bytes,
  name : String,
  sparse : Bool,
) -> BinaryResult {
  binary(() => {
    @mat.write_document(@mat.read_document(bytes).convert_storage(name, sparse))
  })
}

///|
#export_name("mat_to_snapshot")
pub fn mat_to_snapshot(bytes : Bytes) -> String {
  @wire.to_snapshot(@mat.read_document(bytes).variables) catch {
    error => @wire.error_json(error).stringify()
  }
}

///|
#export_name("snapshot_to_mat")
pub fn snapshot_to_mat(text : String) -> BinaryResult {
  binary(() => @mat.write_document(@wire.from_snapshot(text)))
}

///|
#export_name("compare_mat")
pub fn compare_mat(left : Bytes, right : Bytes) -> String {
  @wire.diff_json(
    @mat.compare_documents(@mat.read_document(left), @mat.read_document(right)),
  ).stringify() catch {
    error => @wire.error_json(error).stringify()
  }
}

///|
#export_name("compare_mat_trees")
pub fn compare_mat_trees(
  left : Bytes,
  right : Bytes,
  max_samples : Int,
) -> String {
  @wire.tree_diff_json(
    @mat.compare_trees(
      @mat.read_tree(left),
      @mat.read_tree(right),
      max_samples~,
    ),
  ).stringify() catch {
    error => @wire.error_json(error).stringify()
  }
}

///|
#export_name("mat_to_tree_snapshot")
pub fn mat_to_tree_snapshot(bytes : Bytes) -> String {
  @wire.to_tree_snapshot(@mat.read_tree(bytes).variables) catch {
    error => @wire.error_json(error).stringify()
  }
}

///|
#export_name("tree_snapshot_to_mat")
pub fn tree_snapshot_to_mat(text : String) -> BinaryResult {
  binary(() => @mat.write_tree(@wire.from_tree_snapshot(text)))
}

///|
#export_name("make_source")
pub fn make_source(
  size : Int,
  reader : (Int, FixedArray[Byte], Int, Int) -> Int,
) -> @mat.MatSource {
  { size, read_into: reader, }
}

///|
#export_name("inspect_roots_source")
pub fn inspect_roots_source(source : @mat.MatSource) -> String {
  @wire.roots_info(@mat.inspect_roots_from(source)).stringify() catch {
    error => @wire.error_json(error).stringify()
  }
}

///|
#export_name("select_source_mat")
pub fn select_source_mat(
  source : @mat.MatSource,
  names : Array[String],
) -> BinaryResult {
  binary(() => {
    @mat.write_tree(@mat.read_selected_from(source, names).variables, limits={
      ..@mat.default_limits(),
      max_elements: @mat.default_source_limits().max_elements,
    })
  })
}

///|
#export_name("compare_mat_trees_close")
pub fn compare_mat_trees_close(
  left : Bytes,
  right : Bytes,
  options : String,
) -> String {
  @wire.tree_close_json(
    @wire.compare_tree_text(
      @mat.read_tree(left),
      @mat.read_tree(right),
      options,
    ),
  ).stringify() catch {
    error => @wire.error_json(error).stringify()
  }
}

///|
#export_name("inspect_mat_with_options")
pub fn inspect_mat_with_options(bytes : Bytes, name_options : String) -> String {
  try {
    let name_encoding = @wire.name_encoding_options(name_options)

    @wire.tree_info(@mat.read_tree(bytes, name_encoding~)).stringify()
  } catch {
    error => @wire.error_json(error).stringify()
  }
}

///|
#export_name("inspect_roots_with_options")
pub fn inspect_roots_with_options(
  bytes : Bytes,
  name_options : String,
) -> String {
  try {
    let name_encoding = @wire.name_encoding_options(name_options)

    @wire.roots_info(@mat.inspect_roots(bytes, name_encoding~)).stringify()
  } catch {
    error => @wire.error_json(error).stringify()
  }
}

///|
#export_name("mat_to_json_with_options")
pub fn mat_to_json_with_options(bytes : Bytes, name_options : String) -> String {
  try {
    let name_encoding = @wire.name_encoding_options(name_options)

    @wire.to_json(@mat.read_mat(bytes, name_encoding~).arrays).stringify()
  } catch {
    error => @wire.error_json(error).stringify()
  }
}

///|
#export_name("json_to_mat_with_options")
pub fn json_to_mat_with_options(
  text : String,
  name_options : String,
) -> BinaryResult {
  binary(() => {
    let name_encoding = @wire.name_encoding_options(name_options)
    @mat.write_mat(@wire.from_json(text), name_encoding~)
  })
}

///|
#export_name("roundtrip_mat_with_options")
pub fn roundtrip_mat_with_options(
  bytes : Bytes,
  name_options : String,
) -> BinaryResult {
  binary(() => {
    let name_encoding = @wire.name_encoding_options(name_options)
    @mat.write_tree(
      @mat.read_tree(bytes, name_encoding~).variables,
      name_encoding~,
    )
  })
}

///|
#export_name("mat_to_npy_with_options")
pub fn mat_to_npy_with_options(
  bytes : Bytes,
  name : String,
  name_options : String,
) -> BinaryResult {
  binary(() => {
    let name_encoding = @wire.name_encoding_options(name_options)

    let file = @mat.read_document(bytes, name_encoding~)
    match file.get(name) {
      Some(Dense(array)) => @mat.write_npy(array)
      Some(Sparse(_)) =>
        raise @mat.MatError(
          "explicit-densification-required", 0, "Use densify before exporting sparse data to NPY",
        )
      None =>
        raise @mat.MatError("missing-variable", 0, "No variable named: " + name)
    }
  })
}

///|
#export_name("sample_mat_with_options")
pub fn sample_mat_with_options(name_options : String) -> BinaryResult {
  binary(() => {
    let name_encoding = @wire.name_encoding_options(name_options)
    @mat.write_mat(@wire.sample(), name_encoding~)
  })
}

///|
#export_name("select_mat_with_options")
pub fn select_mat_with_options(
  bytes : Bytes,
  names : Array[String],
  name_options : String,
) -> BinaryResult {
  binary(() => {
    let name_encoding = @wire.name_encoding_options(name_options)
    @mat.write_tree(
      @mat.read_selected(bytes, names, name_encoding~).variables,
      name_encoding~,
    )
  })
}

///|
#export_name("npy_to_mat_with_options")
pub fn npy_to_mat_with_options(
  bytes : Bytes,
  name : String,
  name_options : String,
) -> BinaryResult {
  binary(() => {
    let name_encoding = @wire.name_encoding_options(name_options)
    @mat.write_mat([@mat.read_npy(bytes, name)], name_encoding~)
  })
}

///|
#export_name("transform_mat_with_options")
pub fn transform_mat_with_options(
  bytes : Bytes,
  plan : String,
  name_options : String,
) -> BinaryResult {
  binary(() => {
    let name_encoding = @wire.name_encoding_options(name_options)

    @mat.write_document(
      @wire.transform_document(
        @mat.read_document(bytes, name_encoding~).variables,
        plan,
      ),
      name_encoding~,
    )
  })
}

///|
#export_name("compress_mat_with_options")
pub fn compress_mat_with_options(
  bytes : Bytes,
  name_options : String,
) -> BinaryResult {
  binary(() => {
    let name_encoding = @wire.name_encoding_options(name_options)
    @mat.write_tree(
      @mat.read_tree(bytes, name_encoding~).variables,
      compressed=true,
      name_encoding~,
    )
  })
}

///|
#export_name("convert_storage_with_options")
pub fn convert_storage_with_options(
  bytes : Bytes,
  name : String,
  sparse : Bool,
  name_options : String,
) -> BinaryResult {
  binary(() => {
    let name_encoding = @wire.name_encoding_options(name_options)

    @mat.write_document(
      @mat.read_document(bytes, name_encoding~).convert_storage(name, sparse),
      name_encoding~,
    )
  })
}

///|
#export_name("mat_to_snapshot_with_options")
pub fn mat_to_snapshot_with_options(
  bytes : Bytes,
  name_options : String,
) -> String {
  try {
    let name_encoding = @wire.name_encoding_options(name_options)

    @wire.to_snapshot(@mat.read_document(bytes, name_encoding~).variables)
  } catch {
    error => @wire.error_json(error).stringify()
  }
}

///|
#export_name("snapshot_to_mat_with_options")
pub fn snapshot_to_mat_with_options(
  text : String,
  name_options : String,
) -> BinaryResult {
  binary(() => {
    let name_encoding = @wire.name_encoding_options(name_options)
    @mat.write_document(@wire.from_snapshot(text), name_encoding~)
  })
}

///|
#export_name("compare_mat_with_options")
pub fn compare_mat_with_options(
  left : Bytes,
  right : Bytes,
  name_options : String,
) -> String {
  try {
    let name_encoding = @wire.name_encoding_options(name_options)

    @wire.diff_json(
      @mat.compare_documents(
        @mat.read_document(left, name_encoding~),
        @mat.read_document(right, name_encoding~),
      ),
    ).stringify()
  } catch {
    error => @wire.error_json(error).stringify()
  }
}

///|
#export_name("compare_mat_trees_with_options")
pub fn compare_mat_trees_with_options(
  left : Bytes,
  right : Bytes,
  max_samples : Int,
  name_options : String,
) -> String {
  try {
    let name_encoding = @wire.name_encoding_options(name_options)

    @wire.tree_diff_json(
      @mat.compare_trees(
        @mat.read_tree(left, name_encoding~),
        @mat.read_tree(right, name_encoding~),
        max_samples~,
      ),
    ).stringify()
  } catch {
    error => @wire.error_json(error).stringify()
  }
}

///|
#export_name("mat_to_tree_snapshot_with_options")
pub fn mat_to_tree_snapshot_with_options(
  bytes : Bytes,
  name_options : String,
) -> String {
  try {
    let name_encoding = @wire.name_encoding_options(name_options)

    @wire.to_tree_snapshot(@mat.read_tree(bytes, name_encoding~).variables)
  } catch {
    error => @wire.error_json(error).stringify()
  }
}

///|
#export_name("tree_snapshot_to_mat_with_options")
pub fn tree_snapshot_to_mat_with_options(
  text : String,
  name_options : String,
) -> BinaryResult {
  binary(() => {
    let name_encoding = @wire.name_encoding_options(name_options)
    @mat.write_tree(@wire.from_tree_snapshot(text), name_encoding~)
  })
}

///|
#export_name("inspect_roots_source_with_options")
pub fn inspect_roots_source_with_options(
  source : @mat.MatSource,
  name_options : String,
) -> String {
  try {
    let name_encoding = @wire.name_encoding_options(name_options)

    @wire.roots_info(@mat.inspect_roots_from(source, name_encoding~)).stringify()
  } catch {
    error => @wire.error_json(error).stringify()
  }
}

///|
#export_name("select_source_mat_with_options")
pub fn select_source_mat_with_options(
  source : @mat.MatSource,
  names : Array[String],
  name_options : String,
) -> BinaryResult {
  binary(() => {
    let name_encoding = @wire.name_encoding_options(name_options)

    @mat.write_tree(
      @mat.read_selected_from(source, names, name_encoding~).variables,
      limits={
        ..@mat.default_limits(),
        max_elements: @mat.default_source_limits().max_elements,
      },
      name_encoding~,
    )
  })
}

///|
#export_name("compare_mat_trees_close_with_options")
pub fn compare_mat_trees_close_with_options(
  left : Bytes,
  right : Bytes,
  options : String,
  name_options : String,
) -> String {
  try {
    let name_encoding = @wire.name_encoding_options(name_options)

    @wire.tree_close_json(
      @wire.compare_tree_text(
        @mat.read_tree(left, name_encoding~),
        @mat.read_tree(right, name_encoding~),
        options,
      ),
    ).stringify()
  } catch {
    error => @wire.error_json(error).stringify()
  }
}
