function blk_p = getfullnameWithoutLinebreak(blk)
% GETFULLNAMEWITHOUTLINEBREAK Get full path name to block.
% 
%   Has the same functionality as MATLABs built-in function
%   'getfullname()', but removes all line breaks and returns a single line.
%
% Inputs:
%   blk         Handle or path to block
% 
% Outputs:
%   blk_p       Path to block without linebreak
% 
% See also:
%   GETFULLNAME

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2024 Jonas Withelm
%   Copyright (C) 2024 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

blk_p = getfullname(blk);

% replace new line (10, '\n') with space (32, ' ')
if iscell(blk_p)
    blk_p = regexprep(blk_p, '\n', ' ');
else
    blk_p(blk_p==10) = 32;
end

% Performance tests have shown that for cells 'regexprep()' is the fastest
% method, and for a single character array the direct method is the
% fastest.

end
