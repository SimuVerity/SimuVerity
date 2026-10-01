function validateModelBuild(init_script_name)
% validateModelBuild Execute the update model command in Simulink
%   validateModelBuild(init_script_name) runs the given init script and
%   updates the diagram for the corresponding Simulink model.
%   This function should only be called in a UnitTest function.
%   The init script must be equipped with the helper functions clc_clear
%   and open_model to work properly.
%   
% Example for init script:
%   clc_clear;
%   init variables for simulation ...
%   open_model('myAircraftSimulation');
%
% Syntax:
%   c = validateModelBuild(init_script_name)
% 
% Inputs:
%   modelname           name of the model without extension
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

% Set flap to indicate that a unit test is running
assignin('base', 'TEST_LADAC', 1);

% Run the init script
evalin('base', init_script_name);

% Get the modelname the init script has loaded
modelname = evalin('base', 'MODEL_NAME');

% Load the system
load_system(modelname);

% Execute the model update command
set_param(modelname,'SimulationCommand','Update');

% Close the model
close_system(modelname, 0);
close all;

% Clear all variables in the base workspace
evalin('base', 'clear');

end