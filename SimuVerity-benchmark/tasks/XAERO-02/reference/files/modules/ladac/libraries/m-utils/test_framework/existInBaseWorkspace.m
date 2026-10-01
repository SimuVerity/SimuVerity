function varExist = existInBaseWorkspace(varName)
% existInBaseWorkspace Check if a given variable exists in base workspace
%    varExist = existInBaseWorkspace(variable) compares varName and all 
%    variables in base workspace and returns logical 1 (true) if varName 
%    exists, and returns logical 0 (false) otherwise. Either 
%    text input can be a character vector or a string scalar. 
%
% Syntax:
%   c = existInBaseWorkspace('myVariable')
%
% Inputs:
%   variable           name of variable to look for,
%                      char vector
%
% See also:
%   open_model, clc_clear, existInBaseWorkspace
%

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2020-2022 Fabian Guecker
%   Copyright (C) 2022 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

varExist = false;

variable_names = evalin('base', 'who');

for i = 1:length(variable_names)
    if strcmp(variable_names{i}, varName)
        varExist = true;
        return;
    end
end

end