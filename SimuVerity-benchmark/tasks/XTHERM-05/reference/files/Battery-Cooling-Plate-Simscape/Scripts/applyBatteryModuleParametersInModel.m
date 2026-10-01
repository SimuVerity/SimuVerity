function applyBatteryModuleParametersInModel(modelName,batteryLib,capacityCell,options)
% This function applies the block parameters for battery modules in the 
% model containing battery pack with cooling plate subjected to 
% CC-CV charging cycle.
%
%   Inputs:
%       modelName               - Name of the model.
%       batteryLib              - Name of the battery library (E.g. BatteryPack96S3P_lib).
%       capacityCell            - Capacity of each cell in the battery pack.
%
%   Optional inputs:
%       NumThermalNodes          - Number of thermal nodes in the battery pack.
%       BatteryThermalMass       - Thermal mass of each cell.
%       NumThermalModelsEachCell - Number of discretized elements in the
%                                  thermal model of each cell.
%       ThermalConductivityZ     - Thermal conductivity of the cell in the Z dimension.
%       CrossSectionalAreaXY     - Cross-sectional area of the cell in the XY dimension
%       CellHeight               - Height of cell.
%       CoolantResistance        - Cell-level coolant thermal path resistance.
%       InitialSOC               - Initial State of Charge of each cell.
%       InitialTemperature       - Initial temperature of the battery.

% Copyright 2025 - 2026 The MathWorks, Inc.

arguments
    modelName (1,1) string
    batteryLib (1,1) string
    capacityCell (1,1) simscape.Value{simscape.mustBeCommensurateUnit(capacityCell,"A*hr")}
    options.NumThermalNodes (1,1) simscape.Value {simscape.mustBeCommensurateUnit(options.NumThermalNodes,"1")}...
        = simscape.Value(1,"1")
    options.BatteryThermalMass (1,1) simscape.Value{simscape.mustBeCommensurateUnit(options.BatteryThermalMass,"J/K")}...
        = simscape.Value(9000,"J/K")
    options.NumThermalModelsEachCell (1,1) simscape.Value {simscape.mustBeCommensurateUnit(options.NumThermalModelsEachCell,"1")}...
        = simscape.Value(5,"1")
    options.ThermalConductivityZ (1,1) simscape.Value{simscape.mustBeCommensurateUnit(options.ThermalConductivityZ,"W/(K*m)")}...
        = simscape.Value(18,"W/(K*m)")
    options.CrossSectionalAreaXY (1,1) simscape.Value{simscape.mustBeCommensurateUnit(options.CrossSectionalAreaXY,"m^2")}...
        = simscape.Value(3.5e-4,"m^2")
    options.CellHeight (1,1) simscape.Value{simscape.mustBeCommensurateUnit(options.CellHeight,"m")}...
        = simscape.Value(0.2,"m")
    options.CoolantResistance (1,1) simscape.Value{simscape.mustBeCommensurateUnit(options.CoolantResistance,"K/W")}...
        = simscape.Value(1.2,"K/W")
    options.InitialSOC (1,1) simscape.Value{simscape.mustBeCommensurateUnit(options.InitialSOC,"1")}...
        = simscape.Value(0.1,"1")
    options.InitialTemperature (1,1) simscape.Value{simscape.mustBeCommensurateUnit(options.InitialTemperature,"K")}...
        = simscape.Value(298.15,"K")
end

%% Find battery module blocks in the module
moduleRefBlock = strcat(batteryLib,"/Modules/ModuleType1");
batteryModuleBlkPath = string(find_system(modelName, "SearchDepth", 3, ...
    "Type", "Block", "BlockType", "SimscapeBlock", "ReferenceBlock", moduleRefBlock)); % This applies to a module library generated using buildBattery function or Battery Builder app
numModules = numel(batteryModuleBlkPath);

%% Set battery parameters

for i = 1:numModules

    % Set battery capacity
    set_param(batteryModuleBlkPath(i),"BatteryCapacityCell",string(capacityCell.value));

    % Set battery thermal model parameters for height-distributed thermal mass
    set_param(batteryModuleBlkPath(i),"BatteryThermalMassCell",string(options.BatteryThermalMass.value));
    set_param(batteryModuleBlkPath(i),"BatteryThermalMassCell_unit",string(options.BatteryThermalMass.unit));
    set_param(batteryModuleBlkPath(i),"NumThermalModelsCell",string(options.NumThermalModelsEachCell.value));
    set_param(batteryModuleBlkPath(i),"ThermalConductivityZCell",string(options.ThermalConductivityZ.value));
    set_param(batteryModuleBlkPath(i),"ThermalConductivityZCell_unit",string(options.ThermalConductivityZ.unit));
    set_param(batteryModuleBlkPath(i),"CrossSectionalAreaXYCell",string(options.CrossSectionalAreaXY.value));
    set_param(batteryModuleBlkPath(i),"CrossSectionalAreaXYCell_unit",string(options.CrossSectionalAreaXY.unit));
    set_param(batteryModuleBlkPath(i),"HeightCell",string(options.CellHeight.value));
    set_param(batteryModuleBlkPath(i),"HeightCell_unit",string(options.CellHeight.unit));
    set_param(batteryModuleBlkPath(i),"CoolantResistance",string(options.CoolantResistance.value));
    set_param(batteryModuleBlkPath(i),"CoolantResistance_unit",string(options.CoolantResistance.unit));

    % Set battery initial targets
    set_param(batteryModuleBlkPath(i),'socCell_specify','on');
    set_param(batteryModuleBlkPath(i),'socCell_priority','High');
    set_param(batteryModuleBlkPath(i),'socCell',mat2str(repmat(options.InitialSOC.value,1,options.NumThermalNodes.value)));

    set_param(batteryModuleBlkPath(i),'batteryTemperature_specify','on');
    set_param(batteryModuleBlkPath(i),'batteryTemperature_priority','High');
    set_param(batteryModuleBlkPath(i),'batteryTemperature',mat2str(repmat(options.InitialTemperature.value,1,options.NumThermalNodes.value)));
    set_param(batteryModuleBlkPath(i),'batteryTemperature_unit',string(options.InitialTemperature.unit));


end

end