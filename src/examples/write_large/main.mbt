///|
extern "C" fn init_host() -> Unit = "moonmat_init"

///|
#borrow(fallback)
extern "C" fn argument(index : Int32, fallback : String) -> String = "moonmat_arg"

///|
#borrow(path)
extern "C" fn begin_output(path : Bytes) -> Int32 = "moonmat_sink_begin"

///|
#borrow(buffer)
extern "C" fn write_output(
  slot : Int32,
  offset : Int32,
  buffer : FixedArray[Byte],
  start : Int32,
  count : Int32,
) -> Int32 = "moonmat_sink_write"

///|
extern "C" fn finish_output(
  slot : Int32,
  commit : Int32,
  size : Int32,
) -> Int32 = "moonmat_sink_finish"

///|
extern "C" fn stop(code : Int32) -> Unit = "exit"

///|
fn create(
  path : String,
  small : Bool,
  compressed : Bool,
) -> Int32 raise @mat.MatError {
  if path.is_empty() || path.contains("\u{0000}") {
    raise @mat.MatError("invalid-path", 0, "Expected a new output path")
  }
  let byte_count = (if small { 1 } else { 256 }) * 1048576
  // Ownership transfer: the tree retains this payload; it is not changed later.
  let buffer = FixedArray::make(byte_count, b'\x00')
  let limits : @mat.Limits = {
    ..@mat.default_limits(),
    max_file_bytes: 1073741824,
    max_expanded_bytes: 1073741824,
    max_elements: 134217728,
  }
  let array = @mat.raw_array(
    "simulation",
    @mat.Float64,
    [byte_count / 8, 1],
    buffer.unsafe_reinterpret_as_bytes(),
    limits~,
  )
  let slot = begin_output(@utf8.encode((path + "\u{0000}")[:]))
  if slot < 0 {
    raise @mat.MatError("io-error", 0, "Cannot initialize output")
  }
  let mut closed = false
  defer (if !closed { ignore(finish_output(slot, 0, 0)) })
  let sink : @mat.MatSink = {
    write_from: fn(offset, bytes, start, count) {
      write_output(slot, offset, bytes, start, count)
    },
  }
  let size = @mat.write_tree_to([@mat.Numeric(array)], sink, compressed~)
  let status = finish_output(slot, 1, size)
  closed = true
  if status != 0 {
    raise @mat.MatError(
      if status == 3 {
        "output-exists"
      } else {
        "io-error"
      },
      0,
      "Cannot finalize output",
    )
  }
  size
}

///|
fn main {
  init_host()
  let args = @env.args()
  if args.length() < 2 || args.length() > 4 {
    println("write_large OUTPUT.mat [--small] [--compressed]")
    stop(1)
  }
  let path = argument(1, args[1])
  let mut small = false
  let mut compressed = false
  for i = 2; i < args.length(); i = i + 1 {
    let option = argument(i, args[i])
    if option == "--small" && !small {
      small = true
    } else if option == "--compressed" && !compressed {
      compressed = true
    } else {
      println("Expected distinct --small / --compressed options")
      stop(1)
    }
  }
  try {
    let count = create(path, small, compressed)
    println(
      (
        {
          "status": "ok",
          "output": path,
          "bytes": count,
          "input_tree_resident": true,
          "chunk_bytes": 1048576,
          "compressed": compressed,
        } : Json).stringify(),
    )
  } catch {
    error => {
      println(@wire.error_json(error).stringify())
      stop(1)
    }
  }
}
