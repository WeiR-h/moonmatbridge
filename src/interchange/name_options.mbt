///|
/// Codec options are independent of tolerance/report options.
#warnings("-deprecated")
pub fn name_encoding_options(
  text : String,
) -> @mat.NameEncoding raise @mat.MatError {
  if text.length() > 8192 {
    invalid("Name options exceed 8192 characters")
  }
  let value = @json.parse(text[:], max_nesting_depth=4) catch {
    _ => {
      invalid("Invalid name options JSON")
      Json::null()
    }
  }
  let map = object(value)
  reject_unknown(map, ["name_encoding"])
  match map.get("name_encoding") {
    None | Some(String("utf8")) => @mat.Utf8
    Some(String("latin1")) => @mat.Latin1
    _ => {
      invalid("name_encoding must be utf8 or latin1")
      @mat.Utf8
    }
  }
}
