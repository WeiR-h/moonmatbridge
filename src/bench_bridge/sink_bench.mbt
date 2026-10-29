///|
// Development adapter: all fixture and encoder operations remain MoonBit.
fn sink_bench_limits() -> @mat.Limits {
  {
    ..@mat.default_limits(),
    max_file_bytes: 1073741824,
    max_expanded_bytes: 1073741824,
    max_elements: 134217728,
  }
}

///|
fn sink_bench_large_nodes() -> Array[@mat.MatNode] raise @mat.MatError {
  let block = FixedArray::make(32768, b'\x00')
  let mut seed = 20261029U
  for i = 0; i < block.length(); i = i + 1 {
    seed = seed * 1664525U + 1013904223U
    block[i] = (seed >> 24).to_byte()
  }
  let output = FixedArray::make(268435456, b'\x00')
  let pattern = block.unsafe_reinterpret_as_bytes()
  for i = 0; i < 8192; i = i + 1 {
    output.blit_from_bytes(i * 32768, pattern, 0, 32768)
  }
  [
    @mat.Numeric(
      @mat.raw_array(
        "simulation",
        @mat.Float64,
        [33554432, 1],
        output.unsafe_reinterpret_as_bytes(),
        limits=sink_bench_limits(),
      ),
    ),
  ]
}

///|
fn sink_bench_encode(
  nodes : Array[@mat.MatNode],
  old : Bool,
  compressed : Bool,
  sink : @mat.MatSink,
  legacy_writer : (Int32, Bytes, Int32, Int32) -> Int32,
) -> Int32 raise @mat.MatError {
  if !old {
    return @mat.write_tree_to(nodes, sink, compressed~)
  }
  let bytes = @mat.write_tree(nodes, compressed~, limits=sink_bench_limits())
  let mut offset = 0
  while offset < bytes.length() {
    let count = if bytes.length() - offset < 1048576 {
      bytes.length() - offset
    } else {
      1048576
    }
    let mut done = 0
    while done < count {
      let n = legacy_writer(offset + done, bytes, offset + done, count - done)
      if n <= 0 || n > count - done {
        raise @mat.MatError("io-error", offset + done, "Benchmark sink failed")
      }
      done = done + n
    }
    offset = offset + count
  }
  bytes.length()
}

///|
#export_name("sink_prepare")
pub fn sink_prepare(bytes : Bytes) -> Prepared {
  { variables: @mat.read_tree(bytes, limits=sink_bench_limits()).variables, } catch {
    _ => abort("Invalid independent benchmark fixture")
  }
}

///|
#export_name("sink_large")
pub fn sink_large() -> Prepared {
  { variables: sink_bench_large_nodes(), } catch {
    _ => abort("Cannot create large benchmark tree")
  }
}

///|
#export_name("sink_run")
pub fn sink_run(
  value : Prepared,
  old : Bool,
  compressed : Bool,
  writer : (Int32, FixedArray[Byte], Int32, Int32) -> Int32,
  legacy_writer : (Int32, Bytes, Int32, Int32) -> Int32,
) -> String {
  try {
    let sink : @mat.MatSink = { write_from: writer, }
    let size = sink_bench_encode(
      value.variables,
      old,
      compressed,
      sink,
      legacy_writer,
    )
    ({ "status": "ok", "bytes": size } : Json).stringify()
  } catch {
    error => ({ "status": "error", "code": error.code() } : Json).stringify()
  }
}
