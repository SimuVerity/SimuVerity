% Code to initialize parameters for TractorEnergyComputation

% Copyright 2024 - 2025 The MathWorks, Inc.

%% Tractor Parameters

% Engine Parameters
engine.upperLimit           = 2000;                    % (rpm) Maximum engine speed
engine.speedRamp            = 600;                     % (rpm/s) Speed ramp

% Pump parameters
pump.initialDisplacement       = 60;                   % (cm^3/rev) Initial displacement
pump.displacementRamp          = -0.5;                 % (cm^3/(rev*s)) Displacement ramp
pump.positiveDisplacementLimit = 60;                   % (cm^3/rev) Positive displacement limit
pump.negativeDisplacementLimit = 10;                   % (cm^3/rev) Negative displacement limit 
pump.ramp1StartTime            = 1950;                 % (s) Ramp 1 start time 
pump.ramp2StartTime            = 2100;                 % (s) Ramp 2 start time

% Body Parameters

driveline.massTractor         = 2000;                  % (kg) Translational Inertia
driveline.nWheelsPerAxle      = 2;                     % (1) Number of wheels per axle
driveline.distanceFrontAxleCG = 0.85;                  % (m) CG distance from front axle
driveline.distanceRearAxleCG  = 1.12;                  % (m) CG distance from rear axle
driveline.heightCG            = 0.8;                   % (m) CG height from ground
driveline.areaFrontal         = 3;                     % (m^2) Frontal area
driveline.coefficientDrag     = 0.2;                   % (1) Drag coefficient
driveline.densityAir          = 1.15;                  % (kg/m^3) Air density

% Tire Parameters

% Generalised Tire Deflection Chart Parameters
tire.loadVector              = [2.225, 4.45, 6.6725, 8.9, 11.125,...
                               13.35];                 % (kN) Tire load vector
tire.inflationPressureVector = [69, 138, 207, 276,...
                                345];                  % (kPa) Inflation pressure vector
tire.deflectionTable         = [1.896, 1.239, 1.021, 0.894, 0.776;...
                                3.623, 2.423, 1.963, 1.64, 1.435;...
                                5.119, 3.477, 2.77, 2.311, 2.008;...
                                6.447, 4.413, 3.528, 2.939, 2.533;...
                                7.917, 5.306, 4.191, 2.494, 3.03;...
                                9.169, 6.098, 4.851, 4.059, 3.494];
                                                        % (cm) Tire deflection table
tire.contactPatchArea        = [179.93, 145.82, 127.81, 102.68, 100.92;...
                                517.26, 262.89, 211.79, 182.92, 165.86;...
                                726.09, 424.44, 304.42, 241.47, 233.76;...
                                947.36, 604.21, 414.85, 343.35, 297.14;...
                                1085.95, 749.58, 556.91, 443.03, 372.77;...
                                1214.12, 865.65, 649.45, 525.61, 445.5];

% General Tire Parameters
tire.inflationPressure       = 220;                      % (kPa) Tire inflation pressure
tire.constructionCoefficient = 7;                        % (1) Tire construction coefficient
tire.rollingRadiusFront      = 0.45;                     % (m) Front tire rolling radius
tire.rollingRadiusRear       = 0.90;                     % (m) Front tire rolling radius
tire.sectionWidth            = 0.327;                    % (m) Tire section width
tire.sectionHeight           = 0.245;                    % (m) Tire section height

% Scenario Parameters
% Soil property
tire.tc     = 2.2;          % (kN/m^2) Soil cohesion coefficient
tire.tk     = 9;            % (cm) Shear deformation
tire.tphi   = 30;           % (deg) Soil internal friction angle
% Tire-soil interaction parameters
tire.tykc   = 48;           % (kN/tyn^n+1) Tire-soil sinkage cohession moduli
tire.tykphi = 6076;         % (kN/tyn^n+2) Tire-soil sinkage friction moduli
tire.tyn    = 0.781;        % (deg) Tire-soil sinkage exponent

% Final Drive Parameters
finalDrive.gearRatioRear       = 4;                    % (1) Carrier to drive shaft teeth ratio
finalDrive.gearRatioFront      = 2;                    % (1) Carrier to drive shaft teeth ratio
finalDrive.gearRatioFinalDrive = 1;                    % (1) Follower to base teeth ratio
finalDrive.inertiaDriveshaft   = 1;                    % (kg-m^2) Drive shaft inertia

%% Hydrostatic Transmission Parameters
% Pump and Motor Parameters

hydrostaticCVT.displacementPump            = 60;       % (cm^3/rev) Nominal displacement - Pump & Motor
hydrostaticCVT.shaftVelocityNominal        = 1800;     % (rpm) Nominal shaft velocity - Pump & Motor
hydrostaticCVT.nominalPressureGain         = 10;       % (MPa) Nominal pressure gain
hydrostaticCVT.efficiencyVolumetric        = 0.97;     % (1) Volumetric efficiency
hydrostaticCVT.efficiencyMechanical        = 0.92;     % (1) Mechanical efficiecny
hydrostaticCVT.displacementMotor           = 180;      % (cm^3/rev) Nominal displacement
hydrostaticCVT.displacementPumpAux         = 5;        % (cm^3/rev) Nominal displacement - auxiliary pump
hydrostaticCVT.shaftVelocityNominalAux     = 1000;     % (rpm) Nominal shaft velocity - auxiliary pump
hydrostaticCVT.gearRatioAux                = 10;       % (1) Gearbox ratio - auxiliary pump 

% Check Valve Parameters

hydrostaticCVT.pressDifferentialCracking   = 0.03;     % (MPa) Cracking pressure differential
hydrostaticCVT.pressDifferentialMaxOpen    = 0.1;      % (MPa) Maximum opening pressure differential
hydrostaticCVT.areaMax                     = 1e-5;     % (m^2) Maximum opening area
hydrostaticCVT.areaLeak                    = 1e-10;    % (m^2) Leakage area
hydrostaticCVT.cd                          = 0.65;     % (1) Coefficient of discharge

% Relief Valve Parameters

hydrostaticCVT.pressDifferentialSet        = 25;       % (MPa) Set pressure differential
hydrostaticCVT.pressRegulationRange        = 0.35;     % (MPa) Pressure regulation range
hydrostaticCVT.maxArea                     = 2e-5;     % (m^2) Maximum opening area
hydrostaticCVT.pressDifferentialSetAux     = 1;        % (MPa) Set pressure differential - Auxiliary
hydrostaticCVT.pressRegulationRangeAux     = 0.15;     % (MPa) Pressure regulation range - Auxiliary

% Hose Parameters

hydrostaticCVT.lengthPipe                  = 2;        % (m) Length of pipe
hydrostaticCVT.diameterPipe                = 0.05;     % (m) Pipe diameter

%% Implement Parameters

implement.depth1Tillage                    = 9;        % (cm) Tillage depth 1
implement.depth2Tillage                    = 10;       % (cm) Tillage depth 2
implement.depth3Tillage                    = 8;        % (cm) Tillage depth for transmission trade-off study
implement.angleRake                        = 55;       % (deg) Rake angle of implement tool
implement.numberTools                      = 5;        % (1) Number of tools for a narrow implement




