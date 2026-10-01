function [] = blockInitReplaceBlock( block_name, is_type_2, ...
    block_type_1, block_type_2 )
% blockInitReplaceBlock replace top level blocks during block init
% Change type of block with name block_name to block_type_false if
% is_type_true is false or to block_type_true if is_type_true is true.
% 
% Syntax:
%   blockInitReplaceBlock( block_name, is_type_2, block_type_1, ...
%       block_type_2 )
% 
% Inputs:
%   block_name          Name of block (string), e.g. 'my_block'
%   is_type_2           flag that indicates the block type: false -> 
%                       block_type_1, true -> block_type_2
%   block_type_1        first block type (string), e.g. 'Inport'
%   block_type_2        second block type (string), e.g. 'Outport'
% 
% Outputs:
%   -
% 
% See also:
%   blockInitToggleInport, blockInitToggleOutport

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2022 Yannic Beyer
%   Copyright (C) 2022 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

block       = find_system(gcb,'LookUnderMasks','on',...
                'FollowLinks','on','SearchDepth',1,'Name',block_name);
block_type  = get_param( block{1}, 'BlockType' );
if is_type_2
    if strcmp(block_type,block_type_1)
        replace_block(gcb,'SearchDepth',1,'FollowLinks','on', ...
            'Name',block_name,['built-in/',block_type_2],'noprompt');
    end
else
    if strcmp(block_type,block_type_2)
        replace_block(gcb,'SearchDepth',1,'FollowLinks','on', ...
            'Name',block_name,['built-in/',block_type_1],'noprompt')
    end
end

end