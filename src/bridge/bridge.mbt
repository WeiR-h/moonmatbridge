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
  @wire.document_info(@mat.read_document(bytes)).stringify() catch {
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
  binary(() => @mat.write_document(@mat.read_document(bytes).variables))
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
  binary(() => @mat.write_document(@mat.read_document(bytes).select(names)))
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
  binary(() => {
    @mat.write_document(@mat.read_document(bytes).variables, compressed=true)
  })
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
