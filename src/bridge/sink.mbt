///|
#export_name("make_sink")
pub fn make_sink(
  writer : (Int32, FixedArray[Byte], Int32, Int32) -> Int32,
) -> @mat.MatSink {
  { write_from: writer, }
}

///|
fn sink_status(work : () -> Int32 raise @mat.MatError) -> String {
  ({ "status": "ok", "bytes": work(), "version": @mat.version() } : Json).stringify() catch {
    error => @wire.error_json(error).stringify()
  }
}

///|
/// Compatibility output quotas for existing 64 MiB command operations.
fn command_write_limits(selected : Bool) -> @mat.WriteLimits {
  let old = @mat.default_limits()
  {
    ..@mat.default_write_limits(),
    max_output_bytes: old.max_file_bytes,
    max_uncompressed_bytes: old.max_file_bytes,
    max_metadata_bytes: old.max_file_bytes,
    max_elements: if selected {
      @mat.default_source_limits().max_elements
    } else {
      old.max_elements
    },
    max_variables: old.max_variables,
    max_dimensions: old.max_dimensions,
    max_name_bytes: old.max_name_bytes,
  }
}

///|
#export_name("roundtrip_mat_to_with_options")
pub fn roundtrip_mat_to_with_options(
  bytes : Bytes,
  sink : @mat.MatSink,
  options : String,
) -> String {
  sink_status(() => {
    let name_encoding = @wire.name_encoding_options(options)
    @mat.write_tree_to(
      @mat.read_tree(bytes, name_encoding~).variables,
      sink,
      limits=command_write_limits(false),
      name_encoding~,
    )
  })
}

///|
#export_name("roundtrip_mat_to")
pub fn roundtrip_mat_to(bytes : Bytes, sink : @mat.MatSink) -> String {
  roundtrip_mat_to_with_options(bytes, sink, "{}")
}

///|
#export_name("select_source_mat_to_with_options")
pub fn select_source_mat_to_with_options(
  source : @mat.MatSource,
  names : Array[String],
  sink : @mat.MatSink,
  options : String,
) -> String {
  sink_status(() => {
    let name_encoding = @wire.name_encoding_options(options)
    @mat.write_tree_to(
      @mat.read_selected_from(source, names, name_encoding~).variables,
      sink,
      limits=command_write_limits(true),
      name_encoding~,
    )
  })
}

///|
#export_name("select_source_mat_to")
pub fn select_source_mat_to(
  source : @mat.MatSource,
  names : Array[String],
  sink : @mat.MatSink,
) -> String {
  select_source_mat_to_with_options(source, names, sink, "{}")
}

///|
#export_name("tree_snapshot_to_sink_with_options")
pub fn tree_snapshot_to_sink_with_options(
  text : String,
  sink : @mat.MatSink,
  options : String,
) -> String {
  sink_status(() => {
    let name_encoding = @wire.name_encoding_options(options)
    @mat.write_tree_to(
      @wire.from_tree_snapshot(text),
      sink,
      limits=command_write_limits(false),
      name_encoding~,
    )
  })
}

///|
#export_name("tree_snapshot_to_sink")
pub fn tree_snapshot_to_sink(text : String, sink : @mat.MatSink) -> String {
  tree_snapshot_to_sink_with_options(text, sink, "{}")
}
