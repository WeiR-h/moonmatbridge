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
#borrow(path)
extern "C" fn source_open(path : Bytes, limit : Int) -> Int = "moonmat_source_open"

///|
extern "C" fn source_size(handle : Int) -> Int = "moonmat_source_size"

///|
#borrow(buffer)
extern "C" fn source_read(
  handle : Int,
  offset : Int,
  buffer : FixedArray[Byte],
  start : Int,
  length : Int,
) -> Int = "moonmat_source_read"

///|
extern "C" fn source_close(handle : Int) -> Int = "moonmat_source_close"

///|
fn[T] from_file(
  path : String,
  work : (@mat.MatSource) -> T raise @mat.MatError,
) -> T raise @mat.MatError {
  let handle = source_open(
    path_bytes(path),
    @mat.default_source_limits().max_source_bytes,
  )
  if handle < 0 {
    raise @mat.MatError(
      if handle == -2 {
        "file-limit"
      } else {
        "io-error"
      },
      0,
      "Cannot open bounded regular source",
    )
  }
  let source : @mat.MatSource = {
    size: source_size(handle),
    read_into: (offset, buffer, start, count) => {
      source_read(handle, offset, buffer, start, count)
    },
  }
  let mut closed = false
  defer if !closed { ignore(source_close(handle)) }
  let result = work(source)
  let status = source_close(handle)
  closed = true
  if status != 0 {
    raise @mat.MatError("source-changed", 0, "Source changed during reading")
  }
  result
}


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
  "MoonMatBridge v" +
  @mat.version() +
  "\n" +
  "  moonmat info INPUT.mat\n" +
  "  moonmat roots INPUT.mat\n" +
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
  "  moonmat snapshot-tree INPUT.mat OUTPUT.json\n" +
  "  moonmat restore-tree SNAPSHOT.json OUTPUT.mat\n" +
  "  moonmat snapshot INPUT.mat OUTPUT.json\n" +
  "  moonmat restore SNAPSHOT.json OUTPUT.mat\n" +
  "  moonmat diff-tree-close LEFT.mat RIGHT.mat REPORT.json [OPTIONS.json]\n" +
  "  moonmat diff-tree LEFT.mat RIGHT.mat REPORT.json\n" +
  "  moonmat diff LEFT.mat RIGHT.mat [REPORT.json]\n" +
  "  moonmat sample OUTPUT.mat\n" +
  "  moonmat version\n" +
  "Optional prefix: --name-encoding=utf8|latin1\nOutput files must be new. MAT/NPY data remains column-major."
}

///|
fn run_command(
  args : Array[String],
  name_encoding : @mat.NameEncoding,
) -> Unit raise @mat.MatError {
  if args.length() == 1 ||
    (args.length() == 2 && (args[1] == "help" || args[1] == "--help")) {
    println(usage())
    return
  }
  let command = args[1]
  if command == "version" && args.length() == 2 {
    println("MoonMatBridge v" + @mat.version())
  } else if command == "sample" && args.length() == 3 {
    save(args[2], @mat.write_mat(@wire.sample(), name_encoding~))
  } else if command == "info" && args.length() == 3 {
    println(
      @wire.tree_info(@mat.read_tree(read(args[2]), name_encoding~)).stringify(
        indent=2,
      ),
    )
  } else if command == "roots" && args.length() == 3 {
    println(
      @wire.roots_info(
        from_file(args[2], source => {
          @mat.inspect_roots_from(source, name_encoding~)
        }),
      ).stringify(indent=2),
    )
  } else if command == "dump" && args.length() == 4 {
    let document = @wire.to_json(
        @mat.read_mat(read(args[2]), name_encoding~).arrays,
      ).stringify(indent=2) +
      "\n"
    save(args[3], @utf8.encode(document[:]))
  } else if command == "pack" && args.length() == 4 {
    let text = @utf8.decode(read(args[2])[:]) catch {
      _ =>
        raise @mat.MatError("invalid-utf8", 0, "JSON input must be valid UTF-8")
    }
    save(args[3], @mat.write_mat(@wire.from_json(text), name_encoding~))
  } else if command == "snapshot-tree" && args.length() == 4 {
    let text = @wire.to_tree_snapshot(
        @mat.read_tree(read(args[2]), name_encoding~).variables,
      ) +
      "\n"
    save(args[3], @utf8.encode(text[:]))
  } else if command == "restore-tree" && args.length() == 4 {
    let text = @utf8.decode(read(args[2])[:]) catch {
      _ => raise @mat.MatError("invalid-utf8", 0, "Tree snapshot must be UTF-8")
    }
    save(
      args[3],
      @mat.write_tree(@wire.from_tree_snapshot(text), name_encoding~),
    )
  } else if command == "snapshot" && args.length() == 4 {
    let text = @wire.to_snapshot(
        @mat.read_document(read(args[2]), name_encoding~).variables,
      ) +
      "\n"
    save(args[3], @utf8.encode(text[:]))
  } else if command == "restore" && args.length() == 4 {
    let text = @utf8.decode(read(args[2])[:]) catch {
      _ => raise @mat.MatError("invalid-utf8", 0, "Snapshot must be UTF-8")
    }
    save(
      args[3],
      @mat.write_document(@wire.from_snapshot(text), name_encoding~),
    )
  } else if command == "diff-tree-close" &&
    (args.length() == 5 || args.length() == 6) {
    let options = if args.length() == 6 {
      @utf8.decode(read(args[5])[:]) catch {
        _ =>
          raise @mat.MatError(
            "invalid-utf8", 0, "Tolerance options must be UTF-8",
          )
      }
    } else {
      "{}"
    }
    let report = @wire.compare_tree_text(
      @mat.read_tree(read(args[2]), name_encoding~),
      @mat.read_tree(read(args[3]), name_encoding~),
      options,
    )
    let text = @wire.tree_close_json(report).stringify() + "\n"
    save(args[4], @utf8.encode(text[:]))
    if !report.within_tolerance {
      exit_process(2)
    }
  } else if command == "diff-tree" && args.length() == 5 {
    let report = @mat.compare_trees(
      @mat.read_tree(read(args[2]), name_encoding~),
      @mat.read_tree(read(args[3]), name_encoding~),
    )
    let text = @wire.tree_diff_json(report).stringify() + "\n"
    save(args[4], @utf8.encode(text[:]))
    if !report.content_equal {
      exit_process(2)
    }
  } else if command == "diff" && (args.length() == 4 || args.length() == 5) {
    let report = @mat.compare_documents(
      @mat.read_document(read(args[2]), name_encoding~),
      @mat.read_document(read(args[3]), name_encoding~),
    )
    let text = @wire.diff_json(report).stringify() + "\n"
    if args.length() == 5 {
      save(args[4], @utf8.encode(text[:]))
    } else {
      println(text.trim().to_owned())
    }
    if !report.content_equal {
      exit_process(2)
    }
  } else if command == "roundtrip" && args.length() == 4 {
    save(
      args[3],
      @mat.write_tree(
        @mat.read_tree(read(args[2]), name_encoding~).variables,
        name_encoding~,
      ),
    )
  } else if command == "compress" && args.length() == 4 {
    save(
      args[3],
      @mat.write_tree(
        @mat.read_tree(read(args[2]), name_encoding~).variables,
        compressed=true,
        name_encoding~,
      ),
    )
  } else if (command == "sparsify" || command == "densify") &&
    args.length() == 5 {
    save(
      args[4],
      @mat.write_document(
        @mat.read_document(read(args[2]), name_encoding~).convert_storage(
          args[3],
          command == "sparsify",
        ),
        name_encoding~,
      ),
    )
  } else if command == "from-npy" && args.length() == 5 {
    save(
      args[4],
      @mat.write_mat([@mat.read_npy(read(args[2]), args[3])], name_encoding~),
    )
  } else if command == "transform" && args.length() == 5 {
    let plan = @utf8.decode(read(args[3])[:]) catch {
      _ =>
        raise @mat.MatError("invalid-utf8", 0, "Transform plan must be UTF-8")
    }
    save(
      args[4],
      @mat.write_document(
        @wire.transform_document(
          @mat.read_document(read(args[2]), name_encoding~).variables,
          plan,
        ),
        name_encoding~,
      ),
    )
  } else if command == "select" && args.length() >= 5 {
    let names = Array::makei(args.length() - 4, fn(i) { args[i + 4] })
    save(
      args[3],
      @mat.write_tree(
        from_file(args[2], source => {
          @mat.read_selected_from(source, names, name_encoding~)
        }).variables,
        limits={
          ..@mat.default_limits(),
          max_elements: @mat.default_source_limits().max_elements,
        },
        name_encoding~,
      ),
    )
  } else if command == "npy" && args.length() == 5 {
    let file = @mat.read_document(read(args[2]), name_encoding~)
    match file.get(args[3]) {
      Some(Dense(array)) => save(args[4], @mat.write_npy(array))
      Some(Sparse(_)) =>
        raise @mat.MatError(
          "explicit-densification-required", 0, "Use densify before exporting sparse data to NPY",
        )
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

///|
fn run(args : Array[String]) -> Unit raise @mat.MatError {
  if args.length() > 1 && args[1].has_prefix("--name-encoding=") {
    let name_encoding : @mat.NameEncoding = match args[1] {
      "--name-encoding=utf8" => @mat.Utf8
      "--name-encoding=latin1" => @mat.Latin1
      _ =>
        raise @mat.MatError("usage", 0, "Expected --name-encoding=utf8|latin1")
    }
    let rest = Array::makei(args.length() - 1, i => {
      if i == 0 {
        args[0]
      } else {
        args[i + 1]
      }
    })
    run_command(rest, name_encoding)
  } else {
    run_command(args, @mat.Utf8)
  }
}
