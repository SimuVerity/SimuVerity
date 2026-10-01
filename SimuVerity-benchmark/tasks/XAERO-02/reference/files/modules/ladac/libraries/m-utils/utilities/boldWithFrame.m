function out = boldWithFrame(in, padding)
% BOLDWITHFRAME creates a bold string with a surrounding frame.
% 
% Inputs (required):
%   in          String or character array
% 
% Inputs (optional):
%   padding     Horizontal distance between frame and text
% 
% Outputs:
%   out         Processed string or character array with surrounding frame
% 
% See also:
%   BOLD

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2024 Jonas Withelm
%   Copyright (C) 2024 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

if nargin == 1
    padding = 1;
end

n = numel(in);

top_bot = repmat('-', 1, n + 2 + 2*padding);

mid = ['|', repmat(' ', 1, padding), bold(in), repmat(' ', 1, padding), '|'];

out = sprintf('%s\n%s\n%s', top_bot, mid, top_bot);    

end
