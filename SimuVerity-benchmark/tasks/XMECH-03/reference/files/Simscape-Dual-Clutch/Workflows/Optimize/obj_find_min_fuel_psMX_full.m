function F  = obj_find_min_fuel_psMX(model,params_v,rtp,map_h)
% OBJECTIVE FUNCTION TO FIND SHIFT MAP WITH MINIMUM FUEL USE, 20 PARAMETERS
% Copyright 2011-2025 The MathWorks, Inc.

pedalpos = [0.1 0.4 0.5 0.9];

% USE PARAMETER VALUE TO CALCULATE NEW SHIFT MAP
params = reshape(params_v,4,[]);
[Upshift_Speeds, Downshift_Speeds, Pedal_Positions] = Calc_Shift_Map_DL(params,pedalpos);
assignin('base','Upshift_Speeds',Upshift_Speeds);
assignin('base','Downshift_Speeds',Downshift_Speeds);

load_system(model);
set_param(model,'SimulationMode','rapid');

opts = simset('RapidAcceleratorUpToDateCheck', 'off',...
    'ReturnWorkspaceOutputs', 'on','RapidAcceleratorParameterSets',...
    Simulink.BlockDiagram.modifyTunableParameters(rtp, ...
    'Upshift_Speeds',Upshift_Speeds,...
    'Downshift_Speeds',Downshift_Speeds));
out=sim(model,[],opts);

% COMPUTE OBJECTIVE FUNCTION
Fuel_Used_L=out.find('FuelUsedLiters');
F = Fuel_Used_L;

% UPDATE SHIFT MAP PLOT WITH VALUES USED IN THIS OPTIMIZATION STEP
figure(map_h)
Plot_Gear_Shift_Schedule(Pedal_Positions,Upshift_Speeds,Downshift_Speeds);
set(gca,'XLim',[0 120])

% Save results for plotting
assignin('base','tableDeltas',params_v);
assignin('base','fuelUsed',Fuel_Used_L);
evalin('base',['DCT_minFuelOptResMX(end+1).tableDeltas = tableDeltas;']);
evalin('base',['DCT_minFuelOptResMX(end).fuelUsed = fuelUsed;']);

end

