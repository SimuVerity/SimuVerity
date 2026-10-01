function struct_ = double2struct(double_,identifier)

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2020-2022 Yannic Beyer
%   Copyright (C) 2022 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

% identifier = 99999;

struct_ = struct;

i = 1;
while true
    if double_(i) == identifier
        field_name_length = double_(i+1);
        i_name_end = i+field_name_length+1;
        field_name = char(double_(i+2:i_name_end));
        i_field_begin = i_name_end + 1;
        j = i_field_begin;
        while true
            if j == length(double_)
                i_field_end = j;
                break;
            elseif double_(j) == identifier
                i_field_end = j - 1;
                break;
            else
                j = j + 1;
            end
        end       
        if double_(i_field_begin) == identifier + 1
            struct_.(field_name) = double2struct(double_(i_field_begin:i_field_end),identifier+1);
        else
            struct_.(field_name) = double_(i_field_begin:i_field_end);
        end
        i = i_field_end;
    end
    if i == length(double_)
        break;
    end
    i = i + 1;
end

end