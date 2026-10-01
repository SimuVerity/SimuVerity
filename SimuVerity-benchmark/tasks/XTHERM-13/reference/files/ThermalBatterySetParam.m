% Parameter file for residential building heating example using PV charged sand
% thermal energy storage. 
% Design parameters that affect the design of sand pit sizing, water pump, air-blower, pipe fittings and heat
% exchanger

% Copyright 2023 - 2024 The MathWorks, Inc.

% Parameter structures -------------------------------
PVpanel = struct();
heatEx = struct();
tank = struct();
pumps = struct();
TES = struct();
env = struct();

% -------------------------------------------------------------------------
simTinit = 296.15 ; % simulation initial temperature [K]

% Environment-------------------------------------------------------------- 
env.slIrr = [0 0 100 300 500 300 100,0,0]; % Solar irradiation during the day watts/m^2
env.Temp_degC = [15 13 12 15 22 24 20 17 15]; % Atmospheric temperature variation during the day
env.hrs = hours(0:3:24); % Arry of clock time during the day when temperature and solar irradiation is measured 
env.cAir = 1005.4; % Heat capacity of air at 273 K [J/(kg*K)]
env.denseAir = 1.25; % Density of air [kg/m^3] 

% Photovoltaic solar panel-------------------------------------------------
PVpanel.reflectivity = 0.1;
PVpanel.Vm = 38.8; % PV panel load voltage for maximum power [V]
PVpanel.power = 355; % PV panel rated maximum powet [W]
% PV-Initial temperatures [K]
PVpanel.initial.Tg0 = 295; % Glass cover
PVpanel.initial.Tpv0 = 295; % PV cells
PVpanel.initial.Te0 = 295; % Heat exchanger
PVpanel.initial.Tw0 = 295; % Water in the tank
PVpanel.initial.Tb0 = 295; % Back cover
% PV-Geometry
PVpanel.geometry.nSeries = 72; % Number of cells in series (cells in a panel)
PVpanel.geometry.areaPanel = 1.956*0.992; % Panel area[m^2]
PVpanel.geometry.nPrlStr = 25; % Number of panels 
% PV-Heat transfer properties
PVpanel.heatTransfer.Mg = 4;   % Mass of glass cover [kg]
PVpanel.heatTransfer.Mpv = 0.2; % Mass of one PV panel [kg]
PVpanel.heatTransfer.Me = 15; % Mass of heat exchanger [kg]
PVpanel.heatTransfer.Mb = 5; % Mass of back cover [kg]
PVpanel.heatTransfer.tubeCS = 0.01; % Cross section area of the PV Panel cooling tube [m^2]
PVpanel.heatTransfer.tubeHD = 0.1; % Hydraulic diameter of the PV Panel cooling tube [m]
PVpanel.heatTransfer.Cg = 800; % Specific heat of glass [J/kg*K]
PVpanel.heatTransfer.Cpv = 200; % Specific heat of PV cell [J/kg*K]
PVpanel.heatTransfer.Ce = 460; % Specific heat of heat exchanger [J/kg*K]
PVpanel.heatTransfer.Cb = 400; % Specific heat of back cover [J/kg*K]
PVpanel.heatTransfer.epsg = 0.75; % Emissivity of glass
PVpanel.heatTransfer.epspv = 0.7; % Emissivity of PV cell
PVpanel.heatTransfer.hga = 10; % Free convection coefficient between PV cells and ambient air [W/m^2*K]
PVpanel.heatTransfer.hba = 10; % Free convection coefficient between back cover and ambient air [W/m^2*K]
PVpanel.heatTransfer.ke = 130; % Thermal conductivity of water tube 
PVpanel.heatTransfer.Le = 0.04; % Thickness of water tube [m]
PVpanel.heatTransfer.kins = 0.1; % Thermal conductivity of insulation layer [W/m/K]
PVpanel.heatTransfer.Lins = 0.03; % Thickness of insulation layer [m]

% Tank params -------------------------------------------------------------
tank.Volmax = 0.6;  % Maximum tank capacity [m^3]
tank.Tset_degC = 80; % Hot water tank set point temperature
tank.Atank = 0.5;  % Tank cross-sectional area [m^2]
tank.hgtVec = [0.01,0.7,0.5]; % Inlet height vector for the tank
tank.inAreaVec = [0.01,0.01,0.01]; % Inlet area vector for the tank
tank.Htank0 = 0.9;  % Initial water level in the tank [m]
tank.Ttank0 = simTinit; % Initial temperature in the tank [K]
tank.Lins = 0.05; % Insulating layer thickness [m]
tank.kins = 0.1; % Thermal conductivity of insulation layer [W/m/K]
tank.hta = 10; % Free convection coefficient between tank and ambient air [W/m^2/K]

% sand Thermal energy storage (TES) parameters-----------------------------
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
TES.initTemp_degC = 25; % Initial cell temperature [degC]
TES.insuConduct = 3e-3; % Thermal conductivity of thermal insulation to ground [W/m K]
TES.insuThick = 0.2; % Thickness of thermal insulation material
TES.pitA = 36; % Pit wall area [m^2]
TES.filamentMesTC = 90; % Filament temperature measurement instrument time constant %  

% Pump flow control params --------------------------------------------------
pumps.wtrPrLim = 200000; % Pressure limit for the water pump controller [Pa]
pumps.pumpActuatorDelay = 1; % Time constant for the pump actuator
pumps.maxBlowerFlow = 150; % Air flow limit for the blower control [cfm] 
pumps.blowrPrCoff = 769.231; % Blower static pressure coefficient (assuming linear flow vs static pressure characteristics for the blower) [Pa/cfm]
pumps.valveTlimit = 5 ; % PV panel and water temperature difference to open the valve [deg_C]
pumps.roomTempMeasTime = 0.1 ; % Time constant for hot water tank temperature measurement device.
pumps.PVtempMeasTime = 0.0001 ;

% Heat exchanger parameters------------------------------------------------
heatEx.config.airInOut = 0.5; % Air inlet and outlet port area [m^2]
heatEx.config.waterInOut = 0.1; % Water inlet and outlet port area [m^2]
% HEX- Water tube parameters
heatEx.water.numTube = 225; % Number of tubes 
heatEx.water.lenTube = 1.5; % Length of each tube [m]
heatEx.water.diaTube = 0.025; % Diameter of the tube [m]
heatEx.water.foulFac = 0.1; % Fouling factor of tube  
heatEx.water.initTemp = simTinit; % Initial temperature of water in the HE tubes
heatEx.air.initTemp = simTinit; % Initial temperature of air in the HE tubes
% HEX- Air chamber parameters
heatEx.air.minArea = 0.01; % Minimum free-flow area [m^2]
heatEx.air.htArea = 0.5*26.5; % Heat Transfer area without fins [m^2]
heatEx.air.volAir = 0.5; % Moist air volume inside heat exchanger [m^3]
heatEx.air.finSur = 1.125; % Total fin surface area [m^2]
heatEx.air.finEffi = 0.5; % Fin efficiency
heatEx.air.prLossC = 0.25; % Pressure loss coefficient 
heatEx.air.htcCoff = [0.023,0.8,0.33]; % Air side Heat transfer coefficients  [W/K-m^2]
