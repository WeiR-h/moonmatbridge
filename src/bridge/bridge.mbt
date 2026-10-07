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
        { "status": "ok", "bytes": result.data.length(), "version": @mat.version() } :
        Json).stringify()
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
  @wire.info(@mat.read_mat(bytes)).stringify() catch {
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
  binary(() => @mat.write_mat(@mat.read_mat(bytes).arrays))
}

///|
#export_name("mat_to_npy")
pub fn mat_to_npy(bytes : Bytes, name : String) -> BinaryResult {
  binary(() => {
    let file = @mat.read_mat(bytes)
    match file.get(name) {
      Some(array) => @mat.write_npy(array)
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
