function applyBatteryChargeCycleParametersInModel(modelName,batteryPackData,options)
% This function applies the parameters for the battery charge cycle 
% in the model containing battery pack with cooling plate subjected to 
% CC-CV charging cycle.
%
%   Inputs:
%       modelName               - Name of the model.
%       batteryPackData         - simscape.battery.builder.Pack object.
%       options.ChargingEnabled - Charging enabled (=1) or disabled (=0).
%       options.MaxVoltage      - Maximum terminal voltage of each cell.

% Copyright 2025 - 2026 The MathWorks, Inc.

arguments
    modelName (1,1) string
    batteryPackData simscape.battery.builder.Pack
    options.ChargingEnabled (1,1) simscape.Value {simscape.mustBeCommensurateUnit(options.ChargingEnabled,"1")}...
        = simscape.Value(1,"1")
    options.MaxVoltage(1,1) simscape.Value{simscape.mustBeCommensurateUnit(options.MaxVoltage,"V")}...
        = simscape.Value(4.1,"V")
end

%% Estimate battery pack capacity
packCapacity = batteryPackData.CumulativeCellCapacity;

%% Set battery charge cycle parameters
set_param(strcat(modelName,"/Charge On"),'Value',string(options.ChargingEnabled.value));
set_param(strcat(modelName,"/Battery CC-CV"),"MaxCellVoltage", ...
    string(options.MaxVoltage.value));
set_param(strcat(modelName,"/Max Current"),"Value",string(packCapacity.value));
set_param(strcat(modelName,"/Signal Selector/Num of Thermal Nodes"),"Value", ...
    string(batteryPackData.NumModels));

end
