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
#borrow(path)
extern "C" fn sink_bench_begin(path : Bytes) -> Int32 = "moonmat_sink_begin"

///|
#borrow(buffer)
extern "C" fn sink_bench_write(
  slot : Int32,
  offset : Int32,
  buffer : FixedArray[Byte],
  start : Int32,
  count : Int32,
) -> Int32 = "moonmat_sink_write"

///|
#borrow(buffer)
extern "C" fn sink_bench_write_bytes(
  slot : Int32,
  offset : Int32,
  buffer : Bytes,
  start : Int32,
  count : Int32,
) -> Int32 = "moonmat_sink_write"

///|
extern "C" fn sink_bench_finish(
  slot : Int32,
  commit : Int32,
  size : Int32,
) -> Int32 = "moonmat_sink_finish"

///|
#borrow(path)
extern "C" fn sink_bench_remove(path : Bytes) -> Int32 = "moonmat_bench_remove"

///|
fn sink_bench_file(
  nodes : Array[@mat.MatNode],
  old : Bool,
  compressed : Bool,
  path : Bytes,
  file : Bool,
  stats : Array[Int32],
) -> Int32 raise @mat.MatError {
  let slot = if file { sink_bench_begin(path) } else { -1 }
  if file && slot < 0 {
    raise @mat.MatError("io-error", 0, "Cannot create benchmark sink")
  }
  let closed = [false]
  defer (if file && !closed[0] { ignore(sink_bench_finish(slot, 0, 0)) })
  let sink : @mat.MatSink = {
    write_from: fn(offset, buffer, start, count) {
      stats[0] = stats[0] + 1
      if count > stats[1] {
        stats[1] = count
      }
      let n = if file {
        sink_bench_write(slot, offset, buffer, start, count)
      } else {
        count
      }
      if n > 0 {
        stats[2] = stats[2] + n
      }
      n
    },
  }
  let legacy_writer = fn(offset, buffer, start, count) {
    stats[0] = stats[0] + 1
    if count > stats[1] {
      stats[1] = count
    }
    let n = if file {
      sink_bench_write_bytes(slot, offset, buffer, start, count)
    } else {
      count
    }
    if n > 0 {
      stats[2] = stats[2] + n
    }
    n
  }
  let size = sink_bench_encode(nodes, old, compressed, sink, legacy_writer)
  if file {
    let status = sink_bench_finish(slot, 1, size)
    closed[0] = true
    if status != 0 {
      raise @mat.MatError("io-error", 0, "Cannot close benchmark output")
    }
  }
  size
}

///|
fn sink_bench_main() -> Unit {
  let path = host_arg(2, "")
  let old = host_arg(3, "") == "old"
  let compressed = host_arg(4, "") == "compressed"
  let file = host_arg(5, "") == "file"
  let memory = host_arg(6, "") == "memory"
  let target = @utf8.encode((host_arg(7, "") + "\u{0000}")[:])
  try {
    let nodes = if path == "@large" {
      sink_bench_large_nodes()
    } else {
      let bytes = host_read(@utf8.encode((path + "\u{0000}")[:]), 1073741824)
      if host_error() != 0 {
        raise @mat.MatError("io-error", 0, "Cannot read fixture")
      }
      @mat.read_tree(bytes, limits=sink_bench_limits()).variables
    }
    let before = peak()
    let stats = [0, 0, 0]
    let mut output = 0
    let mut owned = false
    let samples = []
    for i = 0; i < (if memory { 1 } else { 15 }); i = i + 1 {
      if owned {
        guard! sink_bench_remove(target) == 0
        owned = false
      }
      stats[0] = 0
      stats[1] = 0
      stats[2] = 0
      let start = now()
      output = sink_bench_file(nodes, old, compressed, target, file, stats)
      let elapsed = now() - start
      owned = file
      if memory || i >= 5 {
        samples.push(elapsed)
      }
    }
    println(
      (
        {
          "status": "ok",
          "samples_ms": Json::array(samples.map(v => Json::number(v))),
          "peak_bytes": peak(),
          "peak_before_bytes": before,
          "output_bytes": output,
          "requests": stats[0],
          "max_request": stats[1],
          "written_bytes": stats[2],
        } : Json).stringify(),
    )
  } catch {
    error =>
      println(({ "status": "error", "code": error.code() } : Json).stringify())
  }
}
