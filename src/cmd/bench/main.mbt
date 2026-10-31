///|
extern "C" fn host_init() -> Unit = "moonmat_init"

///|
extern "C" fn host_arg_count(fallback : Int32) -> Int32 = "moonmat_arg_count"

///|
#borrow(fallback)
extern "C" fn host_arg(index : Int32, fallback : String) -> String = "moonmat_arg"

///|
#borrow(path)
extern "C" fn host_read(path : Bytes, limit : Int32) -> Bytes = "moonmat_read"

///|
extern "C" fn host_error() -> Int32 = "moonmat_error"

///|
extern "C" fn now() -> Double = "moonmat_now"

///|
extern "C" fn peak() -> Double = "moonmat_peak"

///|
fn benchmark_repetitions(text : String) -> Int32 {
  let mut count = 0
  for byte in @utf8.encode(text[:]) {
    if byte < b'0' || byte > b'9' || count > 1024 {
      abort("Invalid benchmark repetition count")
    }
    count = count * 10 + byte.to_int() - 48
  }
  if count < 1 || count > 1024 {
    abort("Benchmark repetitions must be between 1 and 1024")
  }
  count
}

///|
fn execute(
  mode : String,
  bytes : Bytes,
  prepared : Array[@mat.MatNode],
) -> Int32 raise @mat.MatError {
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
  if host_arg_count(0) == 8 && host_arg(1, "") == "sink-write" {
    sink_bench_main()
    return
  }
  if host_arg_count(0) != 4 && host_arg_count(0) != 5 {
    abort("bench INPUT OP timing|memory [REPETITIONS]")
  }
  let path = host_arg(1, "")
  let mode = host_arg(2, "")
  let memory = host_arg(3, "") == "memory"
  let repetitions = if memory {
    1
  } else {
    benchmark_repetitions(host_arg(4, "1"))
  }
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
    let totals = []
    let count = if memory { 1 } else { 10 }
    for _i = 0; _i < count; _i = _i + 1 {
      let start = now()
      let mut value = 0
      for _j = 0; _j < repetitions; _j = _j + 1 {
        value = execute(mode, bytes, prepared)
      }
      let total = now() - start
      checksum = checksum + value
      totals.push(total)
      samples.push(total / repetitions.to_double())
    }
    println(
      (
        {
          "samples_ms": Json::array(samples.map(v => Json::number(v))),
          "samples_total_ms": Json::array(totals.map(v => Json::number(v))),
          "operations_per_sample": repetitions,
          "peak_bytes": peak(),
          "checksum": checksum,
          "input_bytes": bytes.length(),
        } : Json).stringify(),
    )
  } catch {
    _ => abort("Benchmark codec operation failed")
  }
}
