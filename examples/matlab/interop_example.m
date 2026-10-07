% Suggested MATLAB script; not executed in the current validation environment.
% First run: moonmat sample sample.mat
data = load('sample.mat');
assert(isequal(size(data.temperature), [2, 3]));
assert(isa(data.sample_id, 'uint64'));
assert(data.sample_id(1) == bitshift(uint64(1), 53) + uint64(1));
assert(data.spectrum(1) == complex(1, -2));
assert(islogical(data.valid));

if isfile('matlab-data.mat')
    error('Choose a new output filename before running again.');
end
signal = reshape(1:12, [3, 4]);
save('matlab-data.mat', 'signal', '-v7');
disp('Next run: moonmat info matlab-data.mat');
