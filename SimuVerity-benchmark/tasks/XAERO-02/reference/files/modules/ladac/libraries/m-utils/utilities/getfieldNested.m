function f = getfieldNested(s, full_field_path)
% GETFIELDNESTED Returns the field content of a nested structure of
% arbitrary depth with full path as input.
%
% Example:
% f = getfieldNested(s, 'nest1.nest2.nest3') would result in
% f = s.nest1.nest2.nest3
% 
% MATLABS built in function 'getfield' already supports accessing nested
% structures, but requires a different syntax for accessing fields
% (e.g. getfield(struct,'nest1','nest2','nest3')). This function is
% just a wrapper for 'getfield'.
%
% See also: GETFIELD

% ToDo:
% Add support for structure arrays, e.g.:
%   s.nest1.nest2       = 1
%   s.nest1(2).nest2    = 2
%   s(2).nest1.nest2    = 3
%   s(1).nest1(2).nest3 = 4
% Syntax could be getfieldNested(s, 'nest1.nest3', {[1], [2], [1]}) or
% getfieldNested(s, {1}, 'nest1(2).nest3(2)') or direct usage of
% 'getfield'. See 'getfield' before implementation!

delim = '.';

fields = strsplit(full_field_path, delim);
f = getfield(s, fields{:});

end
