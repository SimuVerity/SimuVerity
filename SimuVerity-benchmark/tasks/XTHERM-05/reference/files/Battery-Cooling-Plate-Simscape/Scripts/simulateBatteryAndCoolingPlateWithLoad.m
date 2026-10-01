function simOut = simulateBatteryAndCoolingPlateWithLoad(modelName, ...
    batteryLibName,batteryPackData,stopTime,options)
% This function simulates the model of battery pack integrated with a
% cooling plate for the battery charge cycle.
%
%   Inputs:
%       modelName                      - Name of the model.
%       batteryLibName                 - Name of the battery library.
%       batteryPackData                - simscape.battery.builder.Pack object.
%       stopTime                       - Simulation stop time in seconds.
%       options.SpecificHeatCell       - Specific heat of battery cell.
%       options.BattInitialTemperature - Initial temperature of battery.
%       options.MaxVoltage             - Maximum terminal voltage of each cell.

% Copyright 2025 - 2026 The MathWorks, Inc.

arguments
    modelName (1,1) string
    batteryLibName (1,1) string
    batteryPackData simscape.battery.builder.Pack
    stopTime (1,1) double
    options.SpecificHeatCell (1,1) simscape.Value{simscape.mustBeCommensurateUnit(options.SpecificHeatCell,"J/(kg*K)")}...
        = simscape.Value(1000,"J/(kg*K)")
    options.BattInitialTemperature (1,1) simscape.Value{simscape.mustBeCommensurateUnit(options.BattInitialTemperature,"K")}...
        = simscape.Value(303.15,"K");
    options.MaxVoltage (1,1) simscape.Value{simscape.mustBeCommensurateUnit(options.MaxVoltage,"V")}...
        = simscape.Value(4.1,"V")
end

battCapacityCell = batteryPackData.ModuleAssembly(1).Module(1).ParallelAssembly(1).Cell.Capacity;
massCell = batteryPackData.ModuleAssembly(1).Module(1).ParallelAssembly(1).Cell.Mass;
battThermalMassCell = massCell*options.SpecificHeatCell;
lengthCell = batteryPackData.ModuleAssembly(1).Module(1).ParallelAssembly(1).Cell.Geometry.Length;
thicknessCell = batteryPackData.ModuleAssembly(1).Module(1).ParallelAssembly(1).Cell.Geometry.Thickness;
areaXYCell = lengthCell*thicknessCell; %simscape.Value(0.003,"m^2");

numNodesPerModule = batteryPackData.ModuleAssembly(1).Module(1).NumModels;

% Parameterize the battery modules in the pack
applyBatteryModuleParametersInModel(modelName, batteryLibName, battCapacityCell, ...
    NumThermalNodes=numNodesPerModule, NumThermalModelsEachCell=4, InitialSOC=simscape.Value(0.2,"1"), ...
    BatteryThermalMass=battThermalMassCell, CrossSectionalAreaXY=areaXYCell, ...
    InitialTemperature=options.BattInitialTemperature);

% Apply the battery charge cycle parameters in the model
applyBatteryChargeCycleParametersInModel(modelName,batteryPackData, ...
    "MaxVoltage",options.MaxVoltage);

% Simulate the integrated model for the battery and the cooling plate
% subjected to a CC-CV charging cycle
set_param(modelName, "StopTime", string(stopTime));
simOut = sim(modelName);