% Run manually in MATLAB after producing the roundtrip file with moonmat.
% This script is provided for external validation; it has not been executed here.
function verify_mixed(source_path, roundtrip_path)
    source = load(source_path);
    restored = load(roundtrip_path);
    assert(isequal(fieldnames(source), fieldnames(restored)));
    assert(iscell(restored.measurements));
    assert(isstruct(restored.experiments));
    assert(ischar(restored.title));
    assert(issparse(restored.sparse_signal));
    assert(isa(restored.uint64_ids, 'uint64'));
    names = fieldnames(source);
    for i = 1:numel(names)
        % A legacy object's class definition must be on the MATLAB path to
        % restore its class identity. Without it MATLAB may load it as struct.
        assert(isequaln(source.(names{i}), restored.(names{i})), names{i});
    end
    fprintf('Mixed data verified by MATLAB: %d root variables\n', numel(names));
end
