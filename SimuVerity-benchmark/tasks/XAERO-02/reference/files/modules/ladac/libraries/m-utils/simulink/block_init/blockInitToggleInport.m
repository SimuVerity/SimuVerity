function blockInitToggleInport( inport_name, is_enabled )
% blockInitToggleInport enable or disable inport during block init
%   This function should be called from the initialization of a Simulink
%   block.
%   Enable inport with name inport_name if is_enabled is true or disable
%   inport with name inport_name if is_enabled is false.
% 
% Syntax:
%   blockInitToggleInport( inport_name, is_enabled )
% 
% Input:
%   inport_name             name of the inport block (string), e.g.
%                           'my_inport_block'
%   is_enabled              bolean that indicates whether the inport
%                           should be activated (true) or not (false)
% 
% Output:
%   -
% 
% See also:
%   blockInitReplaceBlock, blockInitToggleOutport

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2022 Yannic Beyer
%   Copyright (C) 2022 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

blockInitReplaceBlock( inport_name, is_enabled, 'Ground', 'Inport' );

end