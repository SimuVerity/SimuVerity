
% Parameter file for sand battery test harness
% Design parameters that affect the design of sand pit sizing, water pump, airblower, pipe fittings and heat
% exchanger

% Copyright 2023-24 The MathWorks, Inc.

TES      = struct();
%% sand Thermal energy storage (TES) parameters
TES.numCoilX = 12; % Number of coils rows perpendicular to flow direction 
TES.numCoilY = 12; % Number of coils in each row
TES.coilWidthHeater = 0.1; % Width(OD) of heating coil [m] 
TES.coilDepthHeater = 1.0; % Depth of heating coil in current flow direction [m]
TES.nTrnsHeater = 20; % Number of heating coil turns in current flow direction 
TES.coilWidthCooler = 0.4; % Width(OD) of cooling coil [m]
TES.coilDepthCooler = 1.0; % Depth of cooling coil in air flow direction [m]
TES.nTrnsCooler = 20; % Number of cooling coil turns in air flow direction 
TES.sandDensity = 1500; % Density of sand [kg/m^3]
TES.sandThCond = 1.2; % Thermal conductivity of sand [W/m*K]
TES.sandSpHeat = 850; % Specific heat of the sand [J/kg*K]
TES.cellRefT = 298.15; % Reference temperature for heating potential [K]
TES.pipeHydraulicDia = 0.1; % Hydraulic diameter of air pipe [m]
TES.heaterTubeDia = 0.01; % Diameter of heater tube [m]
TES.heaterEmissivity = 0.8; % Heater tube emissivity
TES.heaterTimeconst = 1.4; % Heater filament thermal time constant[s] 
TES.heaterRes = 20; % Heater filament electrical resistance [Ohm]
TES.heaterMaxT = 1173; % Heater filament temperature upper limit[K]
TES.initEnergy = 0; % Initial energy stored in the battery [J]
TES.initTemp_degC = 298.15; % Initial cell temperature [degC]
TES.insuConduct = 3e-3; % Thermal conductivity of thermal insulation to ground [W/m K]
TES.insuThick = 0.2; % Thickness of thermal insulation material
TES.pitA = 36; % Pit wall area [m^2]
TES.filamentMesTC = 90; % Filament temperature measurement instrument time constant %