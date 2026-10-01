function is_confirmed = getUserConfirmation(varargin)
% GETUSERCONFIRMATION asks the user for confirmation (yes or no) via the
%   command line.
% 
% Inputs (optional):
%   prompt          Custom prompt (default: 'Do you want to proceed?')
% 
% Outputs:
%   is_confirmed    Boolean, indicating whether the user has confirmed
%                   (true) or denied (false)
% 
% See also:
%   GETUSERCHOICE, GETUSERSELECTION

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2024 Jonas Withelm
%   Copyright (C) 2024 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************


% Input Parser
p = inputParser;
addOptional(p, 'prompt', 'Do you want to proceed?', @(a) ischar(a) || isstring(a));
parse(p, varargin{:});

prompt = p.Results.prompt;

user_choice = getUserChoice(prompt, {'yes', 'no'});

switch user_choice
    case 1
        is_confirmed = true;
    case 2
        is_confirmed = false;
end

end
