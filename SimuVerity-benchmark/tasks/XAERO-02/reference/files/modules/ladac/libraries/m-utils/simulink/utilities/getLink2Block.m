function blk_link = getLink2Block(blk, link_text)
% GETLINK2BLOCK returns a link to the block.
% 
%   This functions returns a link to the block, that, if clicked, opens the
%   block and hilites it in the Simulink model using the 'hilite_system()'
%   function.
% 
% Inputs:
%   blk         Handle or path to a Simulink block
%   link_text   Displayed name of the link
% 
% Outputs:
%   blk_link    Link to the Simulink block
% 
% See also:
%   HILITE_SYSTEM

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2024 Jonas Withelm
%   Copyright (C) 2024 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

blk_p = getfullnameWithoutLinebreak(blk);

if nargin == 2
    blk_link = sprintf('<a href = "matlab:hilite_system(''%s'')">%s</a>', blk_p, link_text);
else
    blk_link = sprintf('<a href = "matlab:hilite_system(''%1$s'')">%1$s</a>', blk_p);
end

end
