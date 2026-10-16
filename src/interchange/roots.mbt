///|
/// Root-only metadata after complete payload/resource validation.
pub fn roots_info(roots : Array[@mat.MatRootInfo]) -> Json {
  {
    "status": "ok",
    "version": @mat.version(),
    "format": "MAT Level 5",
    "roots": Json::array(
      roots.map(fn(root) {
        {
          "name": root.name,
          "class_id": root.class_id,
          "shape": Json::array(root.shape.map(n => Json::number(n.to_double()))),
          "global": root.is_global,
          "complex": root.is_complex,
          "logical": root.is_logical,
          "compressed": root.compressed,
        }
      }),
    ),
  }
}
