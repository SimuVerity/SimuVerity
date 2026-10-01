function array_out = bus2array(bus_,max_array_size)
% bus2array is a similar function to the Simulink block "Bus to Vector",
% but it is not restricted to 1D arrays inside the struct/bus.
% Unfortunately, to run this code in Simulink, you must specify that the
% output of this function is "variable size" and you must specify the
% (maximum) dimension. You can compute the maximum dimension as follows:
% 
% [double_,idx] = struct2double(struct_,identifier);
% max_dimension = [1, length(double_)-length(idx)];
% 

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2020-2022 Yannic Beyer
%   Copyright (C) 2022 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

idx2 = 0;
array_ = zeros(1,max_array_size);
cell_ = struct2cell(bus_);
for i=1:length(cell_)
    sub = cell_{i};
    if isstruct(sub)
        sub_array = bus2array(sub,max_array_size);
    else
        sub_array = sub(:)';
    end
    idx1 = idx2 + 1;
    idx2 = idx2 + length(sub_array);
    array_(idx1:idx2) = sub_array;
end
array_out = array_(1:idx2);