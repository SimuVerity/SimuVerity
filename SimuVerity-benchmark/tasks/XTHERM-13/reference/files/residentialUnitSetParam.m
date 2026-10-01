% Parameter file for residential building heating example using PV charged sand
% thermal energy storage.

% Copyright 2023 - 2024 The MathWorks, Inc.

resUnitParams.lenHouse = 10; % House length [m]
resUnitParams.widHouse = 10; % House width [m]
resUnitParams.htHouse = 5; % House height [m]
resUnitParams.thkWall = 0.2; % Wall thickness [m]
resUnitParams.denseAir = 1.25; % Air density of inside air[kg/m^3]
resUnitParams.wallDensity = 1920; % Wall Density [kg/m^3]
resUnitParams.cWall = 835; % Wall material averaged Specific heat [J/kg/K]
resUnitParams.kWall = 0.038; % Wall material averaged Thermal conductivity [W/m/K]
resUnitParams.thkFloor = 0.038; % Floor thickness above sand thermal battery [m]  
resUnitParams.floorDensity = 1920; % Floor material averaged density [kg/m^3]
resUnitParams.cFloor = 835; % Floor material averaged Specific heat [J/kg/K]
resUnitParams.kFloor = 0.038; % Floor material averaged Thermal conductivity [W/m/K]
resUnitParams.thkRoof = 0.038; % Roof thickness above sand thermal battery [m]  
resUnitParams.roofDensity = 1920; % Roof material averaged density [kg/m^3]
resUnitParams.cRoof = 835; % Roof material averaged Specific heat [J/kg/K]
resUnitParams.kRoof = 0.038; % Roof material averaged Thermal conductivity [W/m/K]
resUnitParams.pitRoof = 40/180/pi; % Roof pitch converted to radians (40 deg)
resUnitParams.areaFracGF = 0.8; % Ground floor carpet area fraction, out of (House length)*(House width)
resUnitParams.numRooms = 4; % Number of rooms at ground floor
resUnitParams.htWindows = 1; % Height of windows [m]
resUnitParams.widWindows = 1; % Width of windows  [m]
resUnitParams.thkWindow = 0.01; % Thickness of windows [m]
resUnitParams.windowDensity = 2700; % Density [kg/m^3]
resUnitParams.cWindow = 840; % Specific heat [J/kg/K]
resUnitParams.kWindow = 0.78;% Thermal conductivity [W/m/K] 
resUnitParams.leakRoofPercent = 0.1; % Leakage % of total air volume  through roof 
resUnitParams.leakWallPercent = 0.15; % Leakage % of total air through walls
resUnitParams.leakWinPercent = 0.2; % Leakage % of total air through windows
resUnitParams.vantilation = 0.35; % Per-hour house air volume replacement fraction
resUnitParams.tHouse = 291.15 ; % Initial house temperature
resUnitParams.tHouseSet_degC = 23; % House set temperature
resUnitParams.avgPowConsumption = 150; % average monthly power consumption [kWh]
% Calculated house parameters
resUnitParams.extVol = resUnitParams.lenHouse*resUnitParams.widHouse*resUnitParams.htHouse; % external volume of the house [m^3]
resUnitParams.wallVol = 2*resUnitParams.thkWall*(resUnitParams.lenHouse +resUnitParams.widHouse)*resUnitParams.htHouse;
resUnitParams.roofVol = 2*resUnitParams.thkRoof*(resUnitParams.widHouse/(2*cos(resUnitParams.pitRoof))*resUnitParams.lenHouse);
resUnitParams.innerVolume = resUnitParams.extVol -(resUnitParams.wallVol + resUnitParams.roofVol);
resUnitParams.leakage = resUnitParams.leakRoofPercent + resUnitParams.leakWallPercent+ resUnitParams.leakWinPercent;
resUnitParams.airCirculation = resUnitParams.innerVolume*(resUnitParams.vantilation+resUnitParams.leakage/100)/3600; % House air circulation rate [m^3/s]
% Room Features
resUnitParams.room.n1Window = 3; % Number of windows in room 1
resUnitParams.room.n2Window = 2; % Number of windows in room 2
resUnitParams.room.n3Window = 2; % Number of windows in room 3
resUnitParams.room.n4Window = 2; % Number of windows in room 4
resUnitParams.room.extArFactor1 = 0.25; % Fraction external house area attached to room 1
resUnitParams.room.extArFactor2 = 0.25; % Fraction external house area attached to room 2
resUnitParams.room.extArFactor3 = 0.25; % Fraction external house area attached to room 3
resUnitParams.room.extArFactor4 = 0.25; % Fraction external house area attached to room 4

% Roof
resUnitParams.roof.thkRoof = 0.2; % Roof thickness [m]
resUnitParams.roof.roofDensity = 32; % Roof density (Glass fiber) [kg/m^3]
resUnitParams.roof.cRoof = 835; % Specific heat [J/kg/K]
resUnitParams.roof.kRoof = 0.038; % Thermal conductivity [W/m/K]

% House Convective heat transfer coefficients [W/M^2/K]
resUnitParams.convc.hAirWall = 8; % Indoor air->walls and windows
resUnitParams.convc.hAirFloor = 15; %Indoor air->floor
resUnitParams.convc.hAirRoof = 12; % Indoor air -> roof
resUnitParams.convc.hWallAtm = 25; % Walls -> atmosphere
resUnitParams.convc.hWindowAtm = 40; % Windows -> atmosphere
resUnitParams.convc.hRoofAtm = 5; % Roof -> atmosphere

% House radiator features
resUnitParams.radiator.powerRating = 5000; % Power rating of radiator [BTU/hr]
resUnitParams.radiator.massPipe = 4.0; % Mass of empty radiator pipe [kg]
resUnitParams.radiator.spHeatPipe = 447.0; % Specific heat of radiator pipe material [j/kg- K]
resUnitParams.radiator.diaPipe = 0.015; % Hydraulic diameter of radiator pipe [m]
resUnitParams.radiator.hRoomAir = 40; % Convective heat transfer coefficient B/W radiator and room air [W/m^2-K]

% Calculated Heat convaction areas of house
resUnitParams.areas.extArea = 2*(resUnitParams.lenHouse + resUnitParams.widHouse)*resUnitParams.htHouse; % Total House external surface area exposed to outside air
resUnitParams.areas.roofArea = 2*(resUnitParams.widHouse/(2*cos(resUnitParams.pitRoof))*resUnitParams.lenHouse); % Total roof area
resUnitParams.areas.gfArea = resUnitParams.areaFracGF*resUnitParams.lenHouse*resUnitParams.widHouse; % Total floor area of the house at ground floor 
resUnitParams.areas.extAreaFrac = 1/resUnitParams.numRooms; % Fraction of external area attached to a single room
resUnitParams.areas.windowArea = resUnitParams.widWindows*resUnitParams.htWindows ; % Window area [m^2]
% Room 1
resUnitParams.areas.areaWindowRoom1 = resUnitParams.room.n1Window * resUnitParams.areas.windowArea;
resUnitParams.areas.areaWallRoom1 = resUnitParams.room.extArFactor1*resUnitParams.areas.extArea - resUnitParams.areas.areaWindowRoom1;
resUnitParams.areas.areaRoofRoom1 = resUnitParams.areas.roofArea/4;
% Room 2
resUnitParams.areas.areaWindowRoom2 = resUnitParams.room.n2Window * resUnitParams.areas.windowArea;
resUnitParams.areas.areaWallRoom2 = resUnitParams.room.extArFactor2*resUnitParams.areas.extArea - resUnitParams.areas.areaWindowRoom2;
resUnitParams.areas.areaRoofRoom2 = resUnitParams.areas.roofArea/4;
% Room 3
resUnitParams.areas.areaWindowRoom3 = resUnitParams.room.n3Window * resUnitParams.areas.windowArea;
resUnitParams.areas.areaWallRoom3 = resUnitParams.room.extArFactor3*resUnitParams.areas.extArea - resUnitParams.areas.areaWindowRoom3;
resUnitParams.areas.areaRoofRoom3 = resUnitParams.areas.roofArea/4;
% Room 4
resUnitParams.areas.areaWindowRoom4 = resUnitParams.room.n4Window;
resUnitParams.areas.areaWallRoom4 = resUnitParams.room.extArFactor4*resUnitParams.areas.extArea - resUnitParams.areas.areaWindowRoom4;
resUnitParams.areas.areaRoofRoom4 = resUnitParams.areas.roofArea/4;

% calculated features 
resUnitParams.areas.areaFloorRm1 = resUnitParams.areas.gfArea/4;
resUnitParams.areas.areaFloorRm2 = resUnitParams.areas.gfArea/4;
resUnitParams.areas.areaFloorRm3 = resUnitParams.areas.gfArea/4;
resUnitParams.areas.areaFloorRm4 = resUnitParams.areas.gfArea/4;
resUnitParams.room.airMassRm1 = resUnitParams.areas.areaFloorRm1 * resUnitParams.htHouse*resUnitParams.denseAir;
resUnitParams.room.airMassRm2 = resUnitParams.areas.areaFloorRm2 * resUnitParams.htHouse*resUnitParams.denseAir;
resUnitParams.room.airMassRm3 = resUnitParams.areas.areaFloorRm3 * resUnitParams.htHouse*resUnitParams.denseAir;
resUnitParams.room.airMassRm4 = resUnitParams.areas.areaFloorRm4 * resUnitParams.htHouse*resUnitParams.denseAir;
resUnitParams.room.wallMassRm1 = resUnitParams.areas.areaWallRoom1 * resUnitParams.thkWall*resUnitParams.wallDensity;
resUnitParams.room.wallMassRm2 = resUnitParams.areas.areaWallRoom2 * resUnitParams.thkWall*resUnitParams.wallDensity;
resUnitParams.room.wallMassRm3 = resUnitParams.areas.areaWallRoom3*resUnitParams.thkWall*resUnitParams.wallDensity;
resUnitParams.room.wallMassRm4 = resUnitParams.areas.areaWallRoom4*resUnitParams.thkWall*resUnitParams.wallDensity;
resUnitParams.room.windowMassRm1 = resUnitParams.areas.areaWindowRoom1*resUnitParams.thkWindow*resUnitParams.windowDensity;
resUnitParams.room.windowMassRm2 = resUnitParams.areas.areaWindowRoom2*resUnitParams.thkWindow*resUnitParams.windowDensity;
resUnitParams.room.windowMassRm3 = resUnitParams.areas.areaWindowRoom3*resUnitParams.thkWindow*resUnitParams.windowDensity;
resUnitParams.room.windowMassRm4 = resUnitParams.areas.areaWindowRoom4*resUnitParams.thkWindow*resUnitParams.windowDensity;
resUnitParams.room.roofMassRm1 = resUnitParams.areas.areaRoofRoom1*resUnitParams.thkRoof*resUnitParams.roofDensity;
resUnitParams.room.roofMassRm2 = resUnitParams.areas.areaRoofRoom2*resUnitParams.thkRoof*resUnitParams.roofDensity;
resUnitParams.room.roofMassRm3 = resUnitParams.areas.areaRoofRoom3*resUnitParams.thkRoof*resUnitParams.roofDensity;
resUnitParams.room.roofMassRm4 = resUnitParams.areas.areaRoofRoom4*resUnitParams.thkRoof*resUnitParams.roofDensity;
resUnitParams.room.floorMassRm1 = resUnitParams.areas.areaFloorRm1*resUnitParams.thkFloor*resUnitParams.floorDensity;
resUnitParams.room.floorMassRm2 = resUnitParams.areas.areaFloorRm2*resUnitParams.thkFloor*resUnitParams.floorDensity;
resUnitParams.room.floorMassRm3 = resUnitParams.areas.areaFloorRm3*resUnitParams.thkFloor*resUnitParams.floorDensity;
resUnitParams.room.floorMassRm4 = resUnitParams.areas.areaFloorRm4*resUnitParams.thkFloor*resUnitParams.floorDensity;
