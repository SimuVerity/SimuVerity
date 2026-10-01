function out = bold(in)
% BOLD creates a bold string.
% 
% Inputs:
%   in      Cell, string or a character array. If the input contains no
%           strings or character arrays, it is returned unchanged
% 
% Outputs:
%   out     Processed cell, string or character array

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2024 Jonas Withelm
%   Copyright (C) 2024 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************


a = '<strong>';
b = '</strong>';

switch class(in)
    
    case 'cell'
        out = in;
        
        for idx = 1:numel(in)
            out{idx} = bold(in{idx});
        end
        
    case {'string', 'char'}
        out = strcat(a, in, b);
        
    otherwise
        out = in;    % Return data unchanged
end

end
