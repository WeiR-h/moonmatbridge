function verify_roundtrip(source_path, restored_path)
  source = load(source_path);
  restored = load(restored_path);
  names = fieldnames(source);
  assert(isequal(names, fieldnames(restored)));
  for i = 1:numel(names)
    check_value(source.(names{i}), restored.(names{i}));
  endfor
  fprintf('Octave %s verified %d variables: %s\n', version(), numel(names), restored_path);
endfunction

function check_value(a, b)
  assert(strcmp(class(a), class(b)));
  assert(isequal(size(a), size(b)));
  assert(issparse(a) == issparse(b));
  if (iscell(a))
    for i = 1:numel(a), check_value(a{i}, b{i}); endfor
  elseif (isstruct(a))
    fields = fieldnames(a);
    assert(isequal(fields, fieldnames(b)));
    for i = 1:numel(a)
      for j = 1:numel(fields), check_value(a(i).(fields{j}), b(i).(fields{j})); endfor
    endfor
  else
    assert(isequaln(a, b));
    if (isfloat(a) && !issparse(a))
      assert(isequal(typecast(real(a(:)), 'uint8'), typecast(real(b(:)), 'uint8')));
      assert(isequal(typecast(imag(a(:)), 'uint8'), typecast(imag(b(:)), 'uint8')));
    endif
  endif
endfunction
