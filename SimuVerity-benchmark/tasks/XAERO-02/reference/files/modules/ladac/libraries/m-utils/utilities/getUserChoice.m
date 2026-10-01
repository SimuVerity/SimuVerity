function user_choice = getUserChoice(varargin)
% GETUSERCHOICE allows the user to select one of the provided options via
%   the command line.
% 
% Inputs:
%   prompt          Prompt to be asked, character vector
%   options         Selection options to be provided, cell array of
%                   character vectors
% 
% Outputs:
%   user_choice     Index of the selected option
% 
% See also:
%   GETUSERSELECTION, GETUSERCONFIRMATION

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2024 Jonas Withelm
%   Copyright (C) 2024 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

% Input Parser
p = inputParser;
addRequired(p, 'prompt',  @(a) ischar(a) || isstring(a));
addRequired(p, 'options', @(a) iscellstr(a) && numel(a) > 1);
parse(p, varargin{:})

prompt  = p.Results.prompt;
options = p.Results.options;

question = sprintf('%s (%s): ', prompt, strjoin(options, '/'));

while true
    user_in = input(question, "s");
    
    idxs = find(strcmpi(user_in, options));

    if isempty(idxs)
        question = 'Wrong answer, please try again: ';
    elseif numel(idxs) == 1
        user_choice = idxs;
        break;
    else
        error('Too many matches!');
    end
end

end
