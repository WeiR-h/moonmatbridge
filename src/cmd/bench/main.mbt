///|
extern "C" fn host_init() -> Unit = "moonmat_init"

///|
extern "C" fn host_arg_count(fallback : Int) -> Int = "moonmat_arg_count"

///|
#borrow(fallback)
extern "C" fn host_arg(index : Int, fallback : String) -> String = "moonmat_arg"

///|
#borrow(path)
extern "C" fn host_read(path : Bytes, limit : Int) -> Bytes = "moonmat_read"

///|
extern "C" fn host_error() -> Int = "moonmat_error"

///|
extern "C" fn now() -> Double = "moonmat_now"

///|
extern "C" fn peak() -> Double = "moonmat_peak"

///|
fn execute(
  mode : String,
  bytes : Bytes,
  prepared : Array[@mat.MatNode],
) -> Int raise @mat.MatError {
  match mode {
    "read" => @mat.read_tree(bytes).variables.length()
    "write" => @mat.write_tree(prepared).length()
    "compress" => @mat.write_tree(prepared, compressed=true).length()
    "select" =>
      @mat.write_tree(@mat.read_selected(bytes, ["v00"]).variables).length()
    _ => abort("Unknown benchmark operation")
  }
}

///|
fn main {
  host_init()
  if host_arg_count(0) != 4 {
    abort("bench INPUT OP timing|memory")
  }
  let path = host_arg(1, "")
  let mode = host_arg(2, "")
  let memory = host_arg(3, "") == "memory"
  let bytes = host_read(@utf8.encode((path + "\u{0000}")[:]), 67108864)
  if host_error() != 0 {
    abort("Cannot read benchmark input")
  }
  try {
    let prepared = if mode == "write" || mode == "compress" {
      @mat.read_tree(bytes).variables
    } else {
      []
    }
    let mut checksum = 0
    if !memory {
      for _i = 0; _i < 5; _i = _i + 1 {
        checksum = checksum + execute(mode, bytes, prepared)
      }
    }
    let samples = []
    let count = if memory { 1 } else { 10 }
    for _i = 0; _i < count; _i = _i + 1 {
      let start = now()
      checksum = checksum + execute(mode, bytes, prepared)
      samples.push(now() - start)
    }
    println(
      (
        {
          "samples_ms": Json::array(samples.map(v => Json::number(v))),
          "peak_bytes": peak(),
          "checksum": checksum,
          "input_bytes": bytes.length(),
        } : Json).stringify(),
    )
  } catch {
    _ => abort("Benchmark codec operation failed")
  }
}
