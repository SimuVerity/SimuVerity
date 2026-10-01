function HydFcnParams = sm_wheel_loader_params_hydr
%% Hydraulic Functions Parameters - Plant
% Lift Actuator
HydFcnParams.liftActuator.rodDiam = 38; % [mm]
HydFcnParams.liftActuator.headDiam = 81; % [mm]
HydFcnParams.liftActuator.stroke = 449; % [mm]
HydFcnParams.liftActuator.headEndArea = pi * (HydFcnParams.liftActuator.headDiam/2)^2; % [mm^2]
HydFcnParams.liftActuator.rodEndArea = pi * (HydFcnParams.liftActuator.headDiam/2)^2 - pi*(HydFcnParams.liftActuator.rodDiam/2)^2; % [mm^2]
HydFcnParams.liftActuator.brkawyToCoulRatio = 1.2;
HydFcnParams.liftActuator.brkawyVel = 1e-4; % [m/s]
HydFcnParams.liftActuator.preloadForce = 20; % [N]
HydFcnParams.liftActuator.coulForceCoef = 1e-4; % [N/Pa]
HydFcnParams.liftActuator.viscCoeff = 5e3; % [N/(m/s)] 
HydFcnParams.liftActuator.mechModelCylOffset = -524; % [mm]
HydFcnParams.liftActuator.mechModelRodOffset = -316; % [mm]
HydFcnParams.liftActuator.initHEPr = 10; % [bar]
HydFcnParams.liftActuator.initREPr = 10; % [bar]

HydFcnParams.liftActuator.maxUpVel = 60; % [mm/s]
HydFcnParams.liftActuator.maxUpQ = (HydFcnParams.liftActuator.maxUpVel * 60 * (HydFcnParams.liftActuator.headEndArea * 2)) / 1e6;
HydFcnParams.liftActuator.maxDownVel = 60; % [mm/s]
HydFcnParams.liftActuator.maxDownQ = (HydFcnParams.liftActuator.maxDownVel * 60 * (HydFcnParams.liftActuator.rodEndArea * 2)) / 1e6;

% Tilt Actuator
HydFcnParams.tiltActuator.rodDiam = 51; % [mm]
HydFcnParams.tiltActuator.rodLength = 550; % [mm]
HydFcnParams.tiltActuator.headDiam = 94; % [mm]
HydFcnParams.tiltActuator.stroke = 350; % [mm]
HydFcnParams.tiltActuator.headEndArea = pi * (HydFcnParams.tiltActuator.headDiam/2)^2; % [mm^2]
HydFcnParams.tiltActuator.rodEndArea = pi * (HydFcnParams.tiltActuator.headDiam/2)^2 - pi*(HydFcnParams.tiltActuator.rodDiam/2)^2; % [mm^2]
HydFcnParams.tiltActuator.brkawyToCoulRatio = 1.2;
HydFcnParams.tiltActuator.brkawyVel = 1e-4; % [m/s]
HydFcnParams.tiltActuator.preloadForce = 20; % [N]
HydFcnParams.tiltActuator.coulForceCoef = 1e-4; % [N/Pa]
HydFcnParams.tiltActuator.viscCoeff = 5e3; % [N/(m/s)] 
HydFcnParams.tiltActuator.mechModelCylOffset = -550; % [mm] -700
HydFcnParams.tiltActuator.mechModelRodOffset = -294; % [mm]
HydFcnParams.tiltActuator.initHEPr = 10; % [bar]
HydFcnParams.tiltActuator.initREPr = 10; % [bar]

% Steer Actuator
HydFcnParams.steerActuator.rodDiam = 32; % [mm]
HydFcnParams.steerActuator.headDiam = 74; % [mm] 81
HydFcnParams.steerActuator.stroke = 250; % [mm]
HydFcnParams.steerActuator.headEndArea = pi * (HydFcnParams.steerActuator.headDiam/2)^2; % [mm^2]
HydFcnParams.steerActuator.rodEndArea = pi * (HydFcnParams.steerActuator.headDiam/2)^2 - pi*(HydFcnParams.steerActuator.rodDiam/2)^2; % [mm^2]
HydFcnParams.steerActuator.brkawyToCoulRatio = 1.2;
HydFcnParams.steerActuator.brkawyVel = 1e-4; % [m/s]
HydFcnParams.steerActuator.preloadForce = 20; % [N]
HydFcnParams.steerActuator.coulForceCoef = 1e-4; % [N/Pa]
HydFcnParams.steerActuator.viscCoeff = 5e3; % [N/(m/s)] 

HydFcnParams.steerActuator.mechModelCylOffset = -380; % [mm]
HydFcnParams.steerActuator.mechModelRodOffset = -255; % [mm]

HydFcnParams.steerActuator.initHEPr = 10*0.1; % [bar]
HydFcnParams.steerActuator.initREPr = 10*0.1; % [bar]

% Valve Spool Vector
spoolPos = (0:0.25:5)'; % [mm] 

% Valve bypass area
BiPArea = [1.75.^flip(spoolPos(2:end)); 1e-3]; % [mm^2] 2.95

% Lift Valve
HydFcnParams.liftValve.spoolPosVector = spoolPos; % [mm]
HydFcnParams.liftValve.BiPOrificeAreaVector = BiPArea; % [mm^2]
HydFcnParams.liftValve.PtoAOrificeAreaVector = [1e-3; 3.0.^spoolPos(2:end)]; % [mm^2] 
HydFcnParams.liftValve.BtoTOrificeAreaVector = [1e-3; 2.5.^spoolPos(2:end)]; % [mm^2] 
HydFcnParams.liftValve.PtoBOrificeAreaVector = [1e-3; 1.0.^spoolPos(2:end)]; % [mm^2] 
HydFcnParams.liftValve.AtoTOrificeAreaVector = [1e-3; 1.5.^spoolPos(2:end)]; % [mm^2] 
HydFcnParams.liftValve.checkValveCrackingPrDiff = 0.001; % [bar]
HydFcnParams.liftValve.checkValveMaxOpeningPrDiff = 0.01; % [bar]
HydFcnParams.liftValve.checkValveMaxOpeningArea = 1100; % [mm^2]
HydFcnParams.liftValve.checkValveLeakageArea = 0.001; % [mm^2]

% Tilt Valve
HydFcnParams.tiltValve.spoolPosVector = spoolPos; % [mm]
HydFcnParams.tiltValve.BiPOrificeAreaVector = BiPArea; % [mm^2]
HydFcnParams.tiltValve.PtoAOrificeAreaVector = [1e-3; 3.0.^spoolPos(2:end)]./2; % [mm^2]
HydFcnParams.tiltValve.BtoTOrificeAreaVector = [1e-3; 2.5.^spoolPos(2:end)]./2; % [mm^2] 
HydFcnParams.tiltValve.PtoBOrificeAreaVector = [1e-3; 1.4.^spoolPos(2:end)]./2; % [mm^2]
HydFcnParams.tiltValve.AtoTOrificeAreaVector = [1e-3; 2.0.^spoolPos(2:end)]./2; % [mm^2]
HydFcnParams.tiltValve.checkValveCrackingPrDiff = 0.001; % [bar]
HydFcnParams.tiltValve.checkValveMaxOpeningPrDiff = 0.01; % [bar]
HydFcnParams.tiltValve.checkValveMaxOpeningArea = 1100; % [mm^2]
HydFcnParams.tiltValve.checkValveLeakageArea = 0.001; % [mm^2]

% Lift & Tilt Flow Divider
HydFcnParams.flowDivider.liftFixedOrificeArea = 20; % [mm^2]
HydFcnParams.flowDivider.tiltFixedOrificeArea = 14; % [mm^2]
HydFcnParams.flowDivider.liftSpoolVec = [-2.5 2.5]; % [mm]
HydFcnParams.flowDivider.liftVarOrificeArea = [20 0.0001]; % [mm^2]
HydFcnParams.flowDivider.tiltSpoolVec = [-2.5 2.5]; % [mm]
HydFcnParams.flowDivider.tiltVarOrificeArea = [0.0001 20]; % [mm^2]
HydFcnParams.flowDivider.actuatorStiffness = 4e4; % [N/m]

% Check Valves
HydFcnParams.checkValves.crackingPrDiff = 0.001*0+0.1/10; % [bar]
HydFcnParams.checkValves.maxOpeningPrDiff = 0.01*0+1/10; % [bar]
HydFcnParams.checkValves.maxOpeningArea = 1200; % [mm^2]
HydFcnParams.checkValves.leakageArea = 0.01; % [mm^2]
HydFcnParams.checkValves.dischargeCoef = 0.7;
HydFcnParams.checkValves.critReynoldsNmbr = 150;
HydFcnParams.checkValves.smoothingFactor = 0.01;

% Actuator Pressure Relief Valves
HydFcnParams.actPRV.reliefPr = 250; % [bar]
HydFcnParams.actPRV.regRange = 5; % [bar]
HydFcnParams.actPRV.maxOpeningArea = 1200; % [mm^2]
HydFcnParams.actPRV.leakageArea = 0.01; % [mm^2]
HydFcnParams.actPRV.dischargeCoef = 0.7;
HydFcnParams.actPRV.critReynoldsNmbr = 150;
HydFcnParams.actPRV.smoothingFactor = 0.01;

% Pump Pressure Relief Valves
HydFcnParams.pumpPRV.reliefPr = 220; % [bar]
HydFcnParams.pumpPRV.regRange = 5; % [bar]
HydFcnParams.pumpPRV.maxOpeningArea = 1200; % [mm^2]
HydFcnParams.pumpPRV.leakageArea = 0.01; % [mm^2]
HydFcnParams.pumpPRV.dischargeCoef = 0.7;
HydFcnParams.pumpPRV.critReynoldsNmbr = 150;
HydFcnParams.pumpPRV.smoothingFactor = 0.01;

% Implement Pump
HydFcnParams.pump.maxSpeed = 2500; % [rpm]
HydFcnParams.pump.maxFlow = 72.3; % [lpm]
HydFcnParams.pump.displacement = (HydFcnParams.pump.maxFlow*1000)/HydFcnParams.pump.maxSpeed; % [cc/rev]
HydFcnParams.pump.nomPrGain = 210; % [bar]
HydFcnParams.pump.nomSpeed = 2200; % [rpm]
HydFcnParams.pump.volEff = 1;
HydFcnParams.pump.mechEff = 1;
HydFcnParams.pump.chamberVol = 1e5; % [mm^3]

% Steering Pump
HydFcnParams.steerPump.maxSpeed = 2500; % [rpm]
HydFcnParams.steerPump.maxFlow = 25*2; % [lpm]
HydFcnParams.steerPump.displacement = (HydFcnParams.steerPump.maxFlow*1000)/HydFcnParams.steerPump.maxSpeed; % [cc/rev]
HydFcnParams.steerPump.nomPrGain = 210; % [bar]
HydFcnParams.steerPump.nomSpeed = 2200; % [rpm]
HydFcnParams.steerPump.volEff = 1;
HydFcnParams.steerPump.mechEff = 1;
HydFcnParams.steerPump.chamberVol = 1e5; % [mm^3]

% Pipes
HydFcnParams.pipes.length = 5e3; % [mm]
HydFcnParams.pipes.hydraulicDiam = 50; % [mm]
HydFcnParams.pipe.crossSectArea = pi * (HydFcnParams.pipes.hydraulicDiam/2)^2; % [mm^2] 

% Steering Orbitrol Valve
HydFcnParams.steerValve.maxRelAngle       = 0.005; % [rad]
HydFcnParams.steerValve.minRelAngle       = -0.005; % [rad]
HydFcnParams.steerValve.sleeveSpringStiff = 4.5e4*0.1*0.75; % [N*m/rad] 4.5e4
HydFcnParams.steerValve.sleeveDamping     = 2e3*0.5;   % [N*m*s/(rad)] 2e3

HydFcnParams.steerValve.hardstopStiff   = 1e4; % [N*m/rad]
HydFcnParams.steerValve.hardstopDamping = 10;  % [N*m*s/rad]


HydFcnParams.steerValve.deadZoneUpperLim = 0.0003; % [rad]
HydFcnParams.steerValve.deadZoneLowerLim = -0.0003; % [rad]
HydFcnParams.steerValve.relAngleGain = 1000; % 
HydFcnParams.steerValve.spoolPosMax = 5; % [mm]
HydFcnParams.steerValve.spoolPosMin = -5; % [mm]

HydFcnParams.steerValve.gerDisplacement = 150; % [cm^3/rev] 
HydFcnParams.steerValve.PtoTDiam = 5; % [mm]
HydFcnParams.steerValve.PtoGerADiam = 5; % [mm]
HydFcnParams.steerValve.PtoGerBDiam = 5; % [mm]
HydFcnParams.steerValve.GerAtoSteerRDiam = 5; % [mm]
HydFcnParams.steerValve.GerBtoSteerLDiam = 5; % [mm]
HydFcnParams.steerValve.TtoSteerLDiam = 5; % [mm]
HydFcnParams.steerValve.TtoSteerRDiam = 5; % [mm]
HydFcnParams.steerValve.gerChamberVol = 1e4; % [mm^3]
HydFcnParams.steerValve.HEOrificeArea = 35; % [mm^2]
HydFcnParams.steerValve.REOrificeArea = 23; % [mm^2]
HydFcnParams.steerValve.CVChamberVol = 1e4; % [mm^3]

%% Hydraulic Functions Parameters - Controller
% Lift Control
HydFcnParams.liftActCtrl.maxSpoolCmd = 5; % [mm]
HydFcnParams.liftActCtrl.minSpoolCmd = -5; % [mm]
HydFcnParams.liftActCtrl.posSpoolCmdRateLimit = 10; % [mm/s]
HydFcnParams.liftActCtrl.negSpoolCmdRateLimit = -10; % [mm/s]

% Tilt Control
HydFcnParams.tiltActCtrl.maxSpoolCmd = 5; % [mm]
HydFcnParams.tiltActCtrl.minSpoolCmd = -5; % [mm]
HydFcnParams.tiltActCtrl.posSpoolCmdRateLimit = 10; % [mm/s]
HydFcnParams.tiltActCtrl.negSpoolCmdRateLimit = -10; % [mm/s]

% Remove temporary variables
