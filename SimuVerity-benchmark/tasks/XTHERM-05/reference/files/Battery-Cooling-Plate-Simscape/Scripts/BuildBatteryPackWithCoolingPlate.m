% This script creates a battery pack with a cooling plate based on the data
% in the BatteryPack96S3PSpecificationData |MAT| file. 
% To create your own battery pack:
%   1) Add/Modify the specifications in the |MAT| file
%   2) Load the |MAT| file, and 
%   3) Run this script.

% Copyright 2025 - 2026 The MathWorks, Inc.

%% Load Battery Pack Specification
load("BatteryPack96S3PSpecificationData");

%% Create Cell Object with PouchGeometry object

% To create the PouchGeometry object, use the batteryPouchGeometry function. 
% Specify the cell height as the first argument, the cell length as the 
% second argument, and the tab location with the name-value argument 
% TabLocation.

pouchGeometry = batteryPouchGeometry(BatteryPackDesign.CellHeight, ...
    BatteryPackDesign.CellLength, BatteryPackDesign.CellThickness, ...
    TabLocation=BatteryPackDesign.CellTabLocation);

% Create a pouch battery cell using this PouchGeometry object
pouchCell = batteryCell(pouchGeometry,Mass=BatteryPackDesign.CellMass,...
    Capacity=BatteryPackDesign.CellCapacity,Energy=BatteryPackDesign.CellEnergy);

% To model the thermal gradient along the cell height of the battery cell, 
% in the BlockParameters property of the CellModelOptions property of the 
% Cell object, set the CellModelBlockPath property to 
% "batt_lib/Cells/Battery Equivalent Circuit" and the ThermalModel property 
% to "HeightDistributedMass".

pouchCell.CellModelOptions.CellModelBlockPath = BatteryPackDesign.CellModelBlockPath;
pouchCell.CellModelOptions.BlockParameters.ThermalModel = BatteryPackDesign.CellThermalModel;

%% Create ParallelAssembly Object

% To create the ParallelAssembly object, use the batteryParallelAssembly 
% function. Define the Cell object as the first argument and the number of 
% cells in parallel as the second argument. To specify the model resolution, 
% use the name-value argument ModelResolution.

parallelAssembly = batteryParallelAssembly(pouchCell,BatteryPackDesign.NumParallelCells,...
     ModelResolution=BatteryPackDesign.ParallelAssyModelResolution);

%% Create Module Object

% To create Module objects, use the batteryModule function. Define the 
% ParallelAssembly object as the first argument and the number of parallel 
% assemblies in series as the second argument. To specify the additional 
% properties, use the name-value arguments InterParallelAssemblyGap and 
% ModelResolution.

groupedModule = batteryModule(parallelAssembly,BatteryPackDesign.NumSeriesAssembliesInModule,...
    InterParallelAssemblyGap=BatteryPackDesign.InterParallelAssemblyGap, ...
    ModelResolution=BatteryPackDesign.ModuleModelResolution, ...
    SeriesGrouping=BatteryPackDesign.ModuleSeriesGrouping);
thermalNodes = groupedModule.ThermalNodes.Bottom;

%% Create ModuleAssembly Object

% To create the ModuleAssembly object, use the batteryModuleAssembly function. 
% Define the Module objects as the first argument. To specify the additional 
% properties, use the name-value arguments CoolantThermalPath and InterModuleGap.

moduleAssembly = batteryModuleAssembly(repmat(groupedModule,1,BatteryPackDesign.NumModules),...
    CoolantThermalPath=BatteryPackDesign.CoolantThermalPath, ...
    InterModuleGap=BatteryPackDesign.InterModuleGap);

%% Create Pack Object

% To create the Pack object, use the batteryPack function and specify the 
% ModuleAssembly object as the first argument. To specify the additional 
% properties, use the name-value arguments CoolantThermalPath and 
% InterModuleAssemblyGap.

pack = batteryPack(repmat(moduleAssembly,1,BatteryPackDesign.NumModuleAssemblies), ...
    CoolantThermalPath=BatteryPackDesign.CoolantThermalPath, ...
    InterModuleAssemblyGap=BatteryPackDesign.InterModuleAssemblyGap);

%% Add Cooling Plate to Pack

% To add a single cooling plate across all battery modules, you must first 
% define a cooling plate boundary. Set the CoolingPlate property of the 
% Pack object to "Bottom".  
pack.CoolingPlate = BatteryPackDesign.CoolingPlate;

% To specify the desired cooling plate block from the Simscape™ Battery™ 
% library, use the CoolingPlateBlockPath property. In this example, you use 
% the Parallel Channels block to model the cooling plate.
pack.CoolingPlateBlockPath = BatteryPackDesign.CoolingPlateBlockPath;

%% Build Simscape model and library of Pack object

% To create a library that contains the Simscape Battery model of the Pack 
% object, use the buildBattery function.
% Create the PouchBatteryPack96S3P_lib and PouchBatteryPack96S3P SLX library files in 
% your working folder. The PouchBatteryPack96S3P_lib library contains the Modules 
% and ParallelAssemblies sublibraries.

buildBattery(pack,LibraryName="PouchBatteryPack96S3P_1", ...
    MaskParameters="VariableNamesByType", ...
    MaskInitialTargets="VariableNamesByInstance", ...
    Verbose="off");