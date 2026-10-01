function setChillerDiameterSDO(chiller_tube_D)
%% Description
% Function used to vary the diameter of the chiller tubes. If the diameter
% changes, other variables have to be adjusted accordingly. Changing
% the chiller diameter will impact on the turbulence and convection
% properties of the coolant and influence the heat exchanged between
% coolant and refrigerant

%% Input:
% chiller_tube_D: [1x1 double]         : diameter of the coolant channel in the chiller in m

%-----------------
% Copyright 2023-2025 The MathWorks, Inc.
%-----------------

%% Implementation
mdlName = bdroot;

% Rounding the diameter to avoid unrealistic values
chiller_tube_D = round(chiller_tube_D,5);

% These parameters are taken as in the parametrization script BEV_Thermal_Management_param
chiller_N_tubes       = 100; % Number of refrigerant tubes
chiller_tube_L        = 0.4; % [m] Length of each refrigerant tube
chiller_N_baffles     = 3;   % Number of coolant baffles

% These parameter depend on the diameter and have to be adjusted
chiller_area_primary  = chiller_N_tubes * pi * chiller_tube_D * chiller_tube_L;                                       % [m^2] Primary heat transfer surface area
chiller_area_baffles  = chiller_N_baffles * 0.7 * 2 * chiller_N_tubes*((2*chiller_tube_D)^2 - pi*chiller_tube_D^2/4); % [m^2] Total surface area of coolant baffles
chiller_tube_Leq      = 2*0.2*chiller_tube_D*chiller_N_tubes;                                                         % [m] Additonal equivalent tube length for losses due to manifold and splits.

% Round the results and assign them as outputs
chiller_tube_Leq     = round(chiller_tube_Leq,5);
chiller_area_baffles = round(chiller_area_baffles,5);
chiller_area_primary = round(chiller_area_primary,5);

% Assign the newly calculated dimensions to the model
sdo.setValueInModel(mdlName,'chiller_area_primary',chiller_area_primary);
sdo.setValueInModel(mdlName,'chiller_area_baffles',chiller_area_baffles);
sdo.setValueInModel(mdlName,'chiller_tube_Leq',chiller_tube_Leq);
sdo.setValueInModel(mdlName,'chiller_tube_D',chiller_tube_D);

end