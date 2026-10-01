function [double_,idx_add] = struct2double( struct_, identifier )

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2020-2022 Yannic Beyer
%   Copyright (C) 2022 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

% identifier = 99999;

output = [];
idx_add = [];

field_names = fieldnames(struct_);

for i = 1:length(field_names)
    idx_add = [idx_add, length(output) + [1,2]];
    output = [output, identifier];
    output = [output, length(field_names{i})];
    idx_add = [idx_add, length(output) + (1:length(field_names{i}))];
    output = [output, double(field_names{i})];
    current_field = struct_.(field_names{i});
    if isstruct(current_field)
        [recursive_output,recursive_idx] = struct2double( current_field, identifier + 1 );
        idx_add = [idx_add, length(output) + recursive_idx];
        output = [output, recursive_output];
    else
        data = double(current_field);
        output = [output, data(:)'];
    end        

end

double_ = output;

end