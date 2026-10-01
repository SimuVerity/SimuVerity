function user_selection = getUserSelection(varargin)
% GETUSERSELECTION allows the user to select any of the provided options
%   via the command line.
% 
% Inputs:
%   prompt          Prompt to be asked, character vector
%   options         Selection options to be provided, cell array of
%                   character vectors
% 
% Outputs:
%   user_selection  Indices of the selected options
% 
% See also:
%   GETUSERCONFIRMATION, GETUSERCHOICE

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2024 Jonas Withelm
%   Copyright (C) 2024 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

% Input Parser
p = inputParser;
addRequired(p, 'prompt',  @(a) ischar(a) || isstring(a));
addRequired(p, 'options', @(a) iscellstr(a) && ~isempty(a));
parse(p, varargin{:})

prompt   = p.Results.prompt;
options  = p.Results.options;
question = 'Please select indices [1, ...]: ';

fprintf('%s:\n', prompt);
for idx = 1:numel(options)
    fprintf(' [%i] %s\n', idx, options{idx});
end

while true
    
    user_in = input(question);
    
    C = unique(user_in);
    
    if isempty(user_in)
        if getUserConfirmation('Empty selection, are you sure?')
            user_selection = [];
            return;
        end
    elseif any(mod(user_in, 1)) || numel(C) ~= numel(user_in) || min(user_in) < 1 || max(user_in) > numel(options)
        question = 'Wrong answer, please try again: ';
    else
        user_selection = C;
        break;
    end
end

end
