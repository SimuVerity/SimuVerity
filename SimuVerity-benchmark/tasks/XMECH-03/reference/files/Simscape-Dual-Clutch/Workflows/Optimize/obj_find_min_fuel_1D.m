function F  = obj_find_min_fuel_1D(rampconst,model,rtp,fuelUse_h,map_h)
% OBJECTIVE FUNCTION TO FIND SHIFT MAP WITH MINIMUM FUEL USE, ONE PARAMETER
% Copyright 2011-2025 The MathWorks, Inc.

% USE PARAMETER VALUE TO CALCULATE NEW SHIFT MAP
[Upshift_Speeds, Downshift_Speeds, Pedal_Positions] = Calc_Shift_Map_RO(rampconst,17);
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

% ADD RESULTS OF CURRENT OPTIMIZATION SIMULATION TO PLOT
figure(fuelUse_h)
hold on
plot(rampconst,Fuel_Used_L,'s',...
    'MarkerEdgeColor','k',...
    'MarkerFaceColor','r',...
    'MarkerSize',10);
legend({'Parameter Sweep','Optimization Search'},'Location','NorthWest');

% UPDATE SHIFT MAP PLOT WITH VALUES USED IN THIS OPTIMIZATION STEP
figure(map_h)
Plot_Gear_Shift_Schedule(Pedal_Positions,Upshift_Speeds,Downshift_Speeds);
set(gca,'XLim',[0 120])

end
