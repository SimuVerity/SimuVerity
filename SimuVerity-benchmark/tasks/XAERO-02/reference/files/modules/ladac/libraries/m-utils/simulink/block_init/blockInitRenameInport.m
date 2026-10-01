function [] = blockInitRenameInport( inport_number, inport_name )
% blockInitRenameInport rename top level inport blocks during block init
%   Rename inport block with port number inport_number to inport_name.
% 
% Syntax:
%   blockInitRenameInport( inport_number, inport_name )
% 
% Inputs:
%   inport_number       port number of the inport block to be renamed
%                       (double)
%   inport_name         new desired name of the specified inport block
%                       (string)
% 
% Outputs:
%   -
% 
% See also:
%   blockInitToggleInport, blockInitReplaceBlock

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2022 Yannic Beyer
%   Copyright (C) 2022 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

block_list  = find_system(gcb,'LookUnderMasks','on','FollowLinks','on',...
    'SearchDepth',1,'BlockType','Inport');

is_success = false;
for i = 1:length(block_list)
    current_inport_number = str2num(get_param(block_list{i},'Port'));
    if current_inport_number == inport_number
        set_param(block_list{i},'Name',inport_name);
        is_success = true;
        break;
    end
end

if ~is_success
    error('blockInitRenameInport: Something went wrong.');
end

end