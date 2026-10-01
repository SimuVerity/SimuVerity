function blockInitToggleOutport( outport_name, is_enabled )
% blockInitToggleOutport enable or disable outport during block init
%   This function should be called from the initialization of a Simulink
%   block.
%   Enable outport with name outport_name if is_enabled is true or delete
%   outport with name outport_name if is_enabled is false.
% 
% Syntax:
%   blockInitToggleOutport( outport_name, is_enabled )
% 
% Input:
%   outport_name            name of the outport block (string), e.g.
%                           'my_outport_block'
%   is_enabled              bolean that indicates whether the outport
%                           should be activated (true) or not (false)
% 
% Output:
%   -
% 
% See also:
%   blockInitReplaceBlock, blockInitToggleInport

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2022 Yannic Beyer
%   Copyright (C) 2022 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

blockInitReplaceBlock( outport_name, is_enabled, 'Terminator', 'Outport' );

end