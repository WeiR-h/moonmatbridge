///|
/// RFC 3629 scalar validation/counting without allocating a decoded String.
fn utf8_scalar_count(data : BytesView) -> Int raise MatError {
  let mut offset = 0
  let mut count = 0
  while offset < data.length() {
    let first = data[offset].to_int()
    let width = if first <= 127 {
      1
    } else if first >= 194 && first <= 223 {
      2
    } else if first >= 224 && first <= 239 {
      3
    } else if first >= 240 && first <= 244 {
      4
    } else {
      0
    }
    if width == 0 || width > data.length() - offset {
      fail("invalid-char", offset, "Malformed UTF-8 character payload")
    }
    for i = 1; i < width; i = i + 1 {
      let value = data[offset + i].to_int()
      if value < 128 || value > 191 {
        fail("invalid-char", offset + i, "Malformed UTF-8 continuation")
      }
    }
    if width > 1 {
      let second = data[offset + 1].to_int()
      if (first == 224 && second < 160) ||
        (first == 237 && second > 159) ||
        (first == 240 && second < 144) ||
        (first == 244 && second > 143) {
        fail(
          "invalid-char", offset, "UTF-8 requires canonical Unicode scalar encoding",
        )
      }
    }
    count = count + 1
    offset = offset + width
  }
  count
}
