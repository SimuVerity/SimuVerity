function bdroot_link = getLink2bdroot(blk, link_text)
% GETLINK2BDROOT returns a link to the top-level model.
% 
%   This functions returns a link to the top-level model of block,
%   that, if clicked, opens the model root using the 'open()'
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

% We need the name and not the handle, therefore getfullname() is used:
model_root = bdroot(getfullname(blk));

if nargin == 2
    bdroot_link = sprintf('<a href = "matlab:open(''%s'')">%s</a>', model_root, link_text);
else
    bdroot_link = sprintf('<a href = "matlab:open(''%1$s'')">%1$s</a>', model_root);
end

end
