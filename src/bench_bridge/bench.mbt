///|
/// Development-only codec benchmark adapter. No filesystem or format logic in JS.
pub struct Prepared {
  priv variables : Array[@mat.MatNode]
}

///|
#export_name("prepare")
pub fn prepare(bytes : Bytes) -> Prepared {
  { variables: @mat.read_tree(bytes).variables, } catch {
    _ => abort("Benchmark fixture must be independently validated")
  }
}

///|
#export_name("read")
pub fn read(bytes : Bytes) -> Int {
  @mat.read_tree(bytes).variables.length() catch {
    _ => abort("Benchmark read failed")
  }
}

///|
#export_name("write")
pub fn write(value : Prepared) -> Int {
  @mat.write_tree(value.variables).length() catch {
    _ => abort("Benchmark write failed")
  }
}

///|
#export_name("compress")
pub fn compress(value : Prepared) -> Int {
  @mat.write_tree(value.variables, compressed=true).length() catch {
    _ => abort("Benchmark compression failed")
  }
}

///|
#export_name("select")
pub fn select(bytes : Bytes) -> Int {
  @mat.write_tree(@mat.read_tree(bytes).select(["v00"])).length() catch {
    _ => abort("Benchmark selection failed")
  }
}
