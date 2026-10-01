function setEvaporatorLengthSDO(evaporator_L)
%% Description    
% Function used to vary the length of the evaporator. If the length
% changes, some other parameters will have to be adjusted. The heat
% exchange increases but at the same time the losses increase.

%% Input:
% evaporator_L: [1x1 double]           : Length of the evaporator in m

%-----------------
% Copyright 2023-2025 The MathWorks, Inc.
%-----------------

%% Implementation
mdlName = bdroot;

% Rounding evaporator length improves stability:
evaporator_L = round(evaporator_L,4);

% These parameters are taken as in the parametrization script BEV_Thermal_Management_param
evaporator_W                = 0.015; % [m] Overall evaporator width
evaporator_H                = 0.2;   % [m] Overall evaporator height
evaporator_N_tubes          = 20;    % Number of refrigerant tubes
evaporator_N_tube_channels  = 12;    % Number of channels per refrigerant tube
evaporator_tube_H           = 0.002; % [m] Height of each refrigerant tube
evaporator_fin_spacing      = 0.0005;% Fin spacing

% The evaporator gap is not impacted by the length but is needed for the next calculations
evaporator_gap_H            = (evaporator_H - evaporator_N_tubes*evaporator_tube_H) / (evaporator_N_tubes - 1); % [m] Height between refrigerant tubes

% These parameters are impacted by the evaporator length and need to be updated
evaporator_air_area_flow    = (evaporator_N_tubes - 1) * evaporator_L * evaporator_gap_H; % [m^2] Air flow cross-sectional area
evaporator_air_area_primary = 2 * (evaporator_N_tubes - 1) * evaporator_W * (evaporator_L + evaporator_gap_H); % [m^2] Primary air heat transfer surface area
evaporator_N_fins           = (evaporator_N_tubes - 1) * evaporator_L / evaporator_fin_spacing; % Total number of fins
evaporator_air_area_fins    = 2 * evaporator_N_fins * evaporator_W * evaporator_gap_H; % [m^2] Total fin surface area
evaporator_tube_area_webs   = 2 * evaporator_N_tubes * (evaporator_N_tube_channels - 1) * evaporator_L * evaporator_tube_H; % [m^2] Total surface area of webs in refrigerant tubes
evaporator_tube_Leq         = 2*(evaporator_H + 20*evaporator_tube_H*evaporator_N_tubes) + (evaporator_N_tube_channels - 1)*evaporator_L*evaporator_tube_H/(evaporator_W + evaporator_tube_H); % [m] Additional equivalent tube length for losses due to manifold, splits, and webs

% Assign the newly calculated dimensions to the model
sdo.setValueInModel(mdlName,'evaporator_air_area_flow',round(evaporator_air_area_flow,4));
sdo.setValueInModel(mdlName,'evaporator_air_area_primary', round(evaporator_air_area_primary,4));
sdo.setValueInModel(mdlName,'evaporator_air_area_fins', round(evaporator_air_area_fins,4));
sdo.setValueInModel(mdlName,'evaporator_tube_area_webs', round(evaporator_tube_area_webs,4));
sdo.setValueInModel(mdlName,'evaporator_tube_Leq', round(evaporator_tube_Leq,4));
sdo.setValueInModel(mdlName,'evaporator_L', evaporator_L);
end