function simInput = setCondenserLength(condenser_L, simInput)
%% Description:
% Function used to vary the length of the condenser. If the length
% changes, other parameters (such as the surface) will have to be adjusted.
% The heat exchange increases but at the same time the losses increase.

%% Input:
% condenser_L: [1x1 double]         : Length of the condenser in m
% simInput   : [1x1 SimulationInput]: Simulation Input object to the model, obtained for example as: simInput = Simulink.SimulationInput(modelName)

%% Output
% simInput   : [1x1 SimulationInput]: Updated Simulation Input

%-----------------
% Copyright 2023-2025 The MathWorks, Inc.
%-----------------

% Rounding the diameter to avoid unrealistic values
condenser_L = round(condenser_L,4);

% These parameters are taken as in the script BEV_Thermal_Management_param
condenser_W                 = 0.015;    % [m] Overall condenser width
condenser_H                 = 0.39;     % [m] Overall condenser height
condenser_N_tubes           = 40;       % Number of refrigerant tubes
condenser_N_tube_channels   = 12;       % Number of channels per refrigerant tube
condenser_tube_H            = 0.002;    % [m] Height of each refrigerant tube
condenser_fin_spacing       = 0.0005;   % [m] Fin spacing

% The condenser gap is not impacted by the length but is needed for the next calculations
condenser_gap_H = (condenser_H - condenser_N_tubes*condenser_tube_H) / (condenser_N_tubes - 1); % [m] Height between refrigerant tubes

% These parameters are impacted by the condenser length and need to be updated
condenser_air_area_flow = (condenser_N_tubes - 1) * condenser_L * condenser_gap_H; % [m^2] Air flow cross-sectional area
condenser_air_area_primary = 2 * (condenser_N_tubes - 1) * condenser_W * (condenser_L + condenser_gap_H); % [m^2] Primary air heat transfer surface area
condenser_N_fins = (condenser_N_tubes - 1) * condenser_L / condenser_fin_spacing; % Total number of fins
condenser_air_area_fins = 2 * condenser_N_fins * condenser_W * condenser_gap_H; % [m^2] Total fin surface area
condenser_tube_area_webs = 2 * condenser_N_tubes * (condenser_N_tube_channels - 1) * condenser_tube_H * condenser_L; % [m^2] Total surface area of webs in refrigerant tubes
condenser_tube_Leq = 2*(condenser_H + 20*condenser_tube_H*condenser_N_tubes)+ (condenser_N_tube_channels - 1)*condenser_L*condenser_tube_H/(condenser_W + condenser_tube_H); % [m] Additional equivalent tube length for losses due to manifold, splits, and webs

% Assign the newly calculated dimensions to the Simulation Input
simInput = simInput.setVariable('condenser_air_area_flow',round(condenser_air_area_flow,4),'Workspace',simInput.ModelName);
simInput = simInput.setVariable('condenser_air_area_primary', round(condenser_air_area_primary,4),'Workspace',simInput.ModelName);
simInput = simInput.setVariable('condenser_N_fins', round(condenser_N_fins,4),'Workspace',simInput.ModelName);
simInput = simInput.setVariable('condenser_air_area_fins', round(condenser_air_area_fins,4),'Workspace',simInput.ModelName);
simInput = simInput.setVariable('condenser_tube_area_webs', round(condenser_tube_area_webs,4),'Workspace',simInput.ModelName);
simInput = simInput.setVariable('condenser_tube_Leq', round(condenser_tube_Leq,4),'Workspace',simInput.ModelName);
simInput = simInput.setVariable('condenser_L', condenser_L,'Workspace',simInput.ModelName);
end