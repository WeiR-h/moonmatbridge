///|
/// Host transport is limited to argv and file I/O. All formats and conversions execute in MoonBit.
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
#borrow(path, data)
extern "C" fn host_save(path : Bytes, data : Bytes, length : Int) -> Int = "moonmat_save"

///|
extern "C" fn host_error() -> Int = "moonmat_error"

///|
#borrow(data)
extern "C" fn host_emit(data : Bytes, length : Int) -> Int = "moonmat_emit_error"

///|
extern "C" fn exit_process(code : Int) -> Unit = "exit"

///|
fn path_bytes(path : String) -> Bytes raise @mat.MatError {
  if path.is_empty() || path.contains("\u{0000}") {
    raise @mat.MatError("invalid-path", 0, "Path is empty or contains NUL")
  }
  @utf8.encode((path + "\u{0000}")[:])
}

///|
fn read(path : String) -> Bytes raise @mat.MatError {
  let bytes = host_read(path_bytes(path), @mat.default_limits().max_file_bytes)
  if host_error() != 0 {
    raise @mat.MatError(
      if host_error() == 2 {
        "file-limit"
      } else {
        "io-error"
      },
      0,
      "Cannot read bounded regular file: " + path,
    )
  }
  bytes
}

///|
fn save(path : String, bytes : Bytes) -> Unit raise @mat.MatError {
  let code = host_save(path_bytes(path), bytes, bytes.length())
  if code != 0 {
    raise @mat.MatError(
      if code == 3 {
        "output-exists"
      } else {
        "io-error"
      },
      0,
      "Cannot create output file: " + path,
    )
  }
  println(
    (
      {
        "status": "ok",
        "output": path,
        "bytes": bytes.length(),
        "version": @mat.version(),
      } : Json).stringify(),
  )
}

///|
fn usage() -> String {
  "MoonMatBridge v" + @mat.version() + "\n" +
  "  moonmat info INPUT.mat\n" +
  "  moonmat dump INPUT.mat OUTPUT.json\n" +
  "  moonmat pack INPUT.json OUTPUT.mat\n" +
  "  moonmat roundtrip INPUT.mat OUTPUT.mat\n" +
  "  moonmat npy INPUT.mat VARIABLE OUTPUT.npy\n" +
  "  moonmat from-npy INPUT.npy VARIABLE OUTPUT.mat\n" +
  "  moonmat select INPUT.mat OUTPUT.mat VARIABLE...\n" +
  "  moonmat transform INPUT.mat PLAN.json OUTPUT.mat\n" +
  "  moonmat compress INPUT.mat OUTPUT.mat\n" +
  "  moonmat sparsify INPUT.mat VARIABLE OUTPUT.mat\n" +
  "  moonmat densify INPUT.mat VARIABLE OUTPUT.mat\n" +
  "  moonmat sample OUTPUT.mat\n" +
  "  moonmat version\n" +
  "Output files must be new. MAT/NPY data remains column-major."
}

///|
fn run(args : Array[String]) -> Unit raise @mat.MatError {
  if args.length() == 1 ||
    (args.length() == 2 && (args[1] == "help" || args[1] == "--help")) {
    println(usage())
    return
  }
  let command = args[1]
  if command == "version" && args.length() == 2 {
    println("MoonMatBridge v" + @mat.version())
  } else if command == "sample" && args.length() == 3 {
    save(args[2], @mat.write_mat(@wire.sample()))
  } else if command == "info" && args.length() == 3 {
    println(@wire.document_info(@mat.read_document(read(args[2]))).stringify(indent=2))
  } else if command == "dump" && args.length() == 4 {
    let document = @wire.to_json(@mat.read_mat(read(args[2])).arrays).stringify(
        indent=2,
      ) +
      "\n"
    save(args[3], @utf8.encode(document[:]))
  } else if command == "pack" && args.length() == 4 {
    let text = @utf8.decode(read(args[2])[:]) catch {
      _ =>
        raise @mat.MatError("invalid-utf8", 0, "JSON input must be valid UTF-8")
    }
    save(args[3], @mat.write_mat(@wire.from_json(text)))
  } else if command == "roundtrip" && args.length() == 4 {
    save(args[3], @mat.write_document(@mat.read_document(read(args[2])).variables))
  } else if command == "compress" && args.length() == 4 {
    save(args[3], @mat.write_document(@mat.read_document(read(args[2])).variables, compressed=true))
  } else if (command == "sparsify" || command == "densify") && args.length() == 5 {
    save(args[4], @mat.write_document(@mat.read_document(read(args[2])).convert_storage(args[3], command == "sparsify")))
  } else if command == "from-npy" && args.length() == 5 {
    save(args[4], @mat.write_mat([@mat.read_npy(read(args[2]), args[3])]))
  } else if command == "transform" && args.length() == 5 {
    let plan = @utf8.decode(read(args[3])[:]) catch {
      _ => raise @mat.MatError("invalid-utf8", 0, "Transform plan must be UTF-8")
    }
    save(args[4], @mat.write_mat(@wire.transform(@mat.read_mat(read(args[2])).arrays, plan)))
  } else if command == "select" && args.length() >= 5 {
    let names = Array::makei(args.length() - 4, fn(i) { args[i + 4] })
    save(args[3], @mat.write_document(@mat.read_document(read(args[2])).select(names)))
  } else if command == "npy" && args.length() == 5 {
    let file = @mat.read_document(read(args[2]))
    match file.get(args[3]) {
      Some(Dense(array)) => save(args[4], @mat.write_npy(array))
      Some(Sparse(_)) => raise @mat.MatError("explicit-densification-required", 0, "Use densify before exporting sparse data to NPY")
      None =>
        raise @mat.MatError(
          "missing-variable",
          0,
          "No variable named: " + args[3],
        )
    }
  } else {
    raise @mat.MatError("usage", 0, usage())
  }
}

///|
fn main {
  host_init()
  let fallback = @env.args()
  let args = Array::makei(host_arg_count(fallback.length()), fn(i) {
    host_arg(i, fallback.get(i).unwrap_or(""))
  })
  run(args) catch {
    error => {
      let text = @wire.error_json(error).stringify() + "\n"
      let bytes = @utf8.encode(text[:])
      ignore(host_emit(bytes, bytes.length()))
      exit_process(1)
    }
  }
}
