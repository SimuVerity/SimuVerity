function open_model(modelname)
% open_model open or load a Simulink model for LADAC unit tests
%   c = open_model( modelname ) opens the model 'modelname'.
%   If the function finds the variable 'TEST_LADAC' in the base workspace,
%   it doesn't open the model and only assigns the 'modelname' to the the
%   variable 'MODEL_NAME' in the base workspace. 
%   That prevents Simulink from opening the model in a window, which saves
%   time when the model should be used for testing purposes.
%   
%   In addition, the model is only opened if it is not already open. This
%   prevents the model from jumping to the model root and to the foreground
%   when the init script is executed again.
% 
% Syntax:
%   c = open_model(modelname)
% 
% Inputs:
%   modelname           name of the model without extension
% 
% See also:
%   clc_clear, existInBaseWorkspace, validateModelBuild
% 

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2020-2022 Fabian Guecker
%   Copyright (C) 2024 Jonas Withelm
%   Copyright (C) 2024 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

if(~existInBaseWorkspace('TEST_LADAC'))
    if bdIsLoaded(modelname)
        if ~strcmp(get_param(modelname,'Shown'), 'on')
            open(modelname)
        end
    else
        open(modelname)
    end
else
    assignin('base', 'MODEL_NAME', modelname);
end

end
