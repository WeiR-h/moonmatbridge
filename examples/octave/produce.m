function produce(destination)
  if (!exist(destination, 'dir')), mkdir(destination); endif
  data = struct();
  types = {'double','single','int8','uint8','int16','uint16','int32','uint32','int64','uint64'};
  for i = 1:numel(types)
    t = types{i};
    data.(['nd_' t]) = cast(reshape(0:7, [2,2,2]), t);
    data.(['empty_' t]) = cast(zeros(0,2,3), t);
  endfor
  data.ids = [bitshift(uint64(1), 53) + uint64(1), intmax('uint64')];
  data.wave = complex([1,-0,3], [2,0,-4]);
  data.mask = logical([1,0;0,1]);
  data.sparse_signal = sparse([1,3], [2,1], [2,-3], 4,3);
  data.sparse_complex = complex(data.sparse_signal, data.sparse_signal * 2);
  data.title = 'research-data';
  data.char_matrix = ['abc'; 'def'];
  data.empty_char = '';
  data.empty_cell = cell(0,2,3);
  data.empty_struct = repmat(struct('signal', [], 'label', ''), [0,2,3]);
  data.records = repmat(struct('id', int32(7), 'label', 'trial', 'payload', []), [2,2]);
  data.measurements = {data.ids, struct('wave', data.wave, 'sparse', data.sparse_signal); 'sample', cell(0,2)};
  data.records(1).payload = data.measurements;
  data.cross_nested = {struct('records', data.records, 'samples', {data.measurements}), data.sparse_signal};
  save('-mat-binary', fullfile(destination, 'octave-v6.mat'), '-struct', 'data');
  save('-mat7-binary', fullfile(destination, 'octave-v7.mat'), '-struct', 'data');
  % Keep the Octave 8.4 producer edge cases as separately executed fixtures.
  % Its short UTF8 matrix length and sparse-logical class disagree with payloads.
  variants = struct('small_char_matrix', ['ab'; 'cd'], 'sparse_logical', logical(data.sparse_signal));
  variant_names = fieldnames(variants);
  for i = 1:numel(variant_names)
    one = struct(); one.(variant_names{i}) = variants.(variant_names{i});
    save('-mat-binary', fullfile(destination, ['producer-' variant_names{i} '-v6.mat']), '-struct', 'one');
    save('-mat7-binary', fullfile(destination, ['producer-' variant_names{i} '-v7.mat']), '-struct', 'one');
  endfor
  fprintf('Octave %s produced %d variables in v6/v7 formats\n', version(), numel(fieldnames(data)));
endfunction
