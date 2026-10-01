%% Description
% This script increases the value of the plate's pipe diameter. This will
% impact how efficiently the battery is cooled down or heated up and will
% also impact the hydraulic losses occurring in the plate pipes

%% Author: Lorenzo Nicoletti
%-----------------
% Copyright 2022-2025 The MathWorks, Inc.
%-----------------

%% 1) Set up the model
% Open and load
clear; modelName = checkModel('BEV_Thermal_Management');

% Set up folder to store results
proj = currentProject; 
saveLabel = strrep(strrep(strrep(char(datetime),'-','_'),':','_'),' ','_');
saveString= [char(proj.RootFolder) filesep 'Workflows' filesep 'Sensitivity' filesep 'results' filesep 'sweepPipeDiam_',saveLabel,'.mat'];

%% 2) Change Plate Diameter
% Variation of plate diameter in m
plateDiam = round(0.004:0.002:0.010,5);

for loopSimIn = 1:numel(plateDiam)
    
    % Show progress
    fprintf('Iteration for Plate Diameter Number %d \n',loopSimIn);

    % Create Simulink Input object and set the scenario
    simInput = Simulink.SimulationInput(modelName);
    simInput = simInput.setPostSimFcn(@(out) postSimFcnEV(out,simInput));
    simInput = setSimInputObj(simInput,'FixAllParam',1,'Scenario','Summer');
    
    % If the plate diameter changes, change also the aggregate length (as it is usually dependent on the diameter) 
    simInput = simInput.setVariable('pipeDiamCoolingPlate',plateDiam(loopSimIn),'Workspace',modelName);
    lengthAddCoolingPlate(loopSimIn) = round(plateDiam(loopSimIn)*12*20,5); % Aggregate length as 2*pDiam*numPipes*20
    simInput = simInput.setVariable('lengthAddCoolingPlate',lengthAddCoolingPlate(loopSimIn),'Workspace',modelName);

    % Simulate the model using the simulation input object
    out(loopSimIn)      = sim(simInput);

    % Store also the simulation input if needed later
    in(loopSimIn)       = simInput;
end

% Save the results in the folder
try
    save(saveString,'out');
catch
    disp('The "results" folder does not exist and is purposely put under gitignore (to avoid loading big data to Git). Create a result folder locally')
end

%% 3) Show Main Results
close all

% Get all heat energies:
heatEnergies = arrayfun(@(p) calcHeatEnergy(p.resultsLogs), out);
resultsLogs  = arrayfun(@(p) p.resultsLogs, out); 
results     =  arrayfun(@(p) p.results, out); 

% As a legend use the heater power in W
labelo   = arrayfun(@(p) [num2str(p*1000),' mm'], plateDiam, 'UniformOutput', false);

% The time it takes for the battery to reach the temperature:
battTime = arrayfun(@(p) checkTempReq([p.resultsLogs.get('tempBattery').Values.Time,p.resultsLogs.get('tempBattery').Values.Data],[5,35]), out);
cabiTime = arrayfun(@(p) checkTempReq([p.resultsLogs.get('tempCabin').Values.Time,p.resultsLogs.get('tempCabin').Values.Data],[24,26]), out);

% PLOT 1: the temperature behavior of the battery
plotTimeData(resultsLogs,"tempBattery",'XLabel','Time in sec','YLabel', 'Temperature in °C','Title','Battery Temperature','Legend',labelo);
if (simInput(1).getVariable('battery_T_init'))<273.15; tempBattObj = 5; else; tempBattObj = 35; end
plot([0, 765], [tempBattObj, tempBattObj], 'r--','DisplayName','Target Temp','LineWidth',2);
plotBarGraph(plateDiam*1000,battTime,'XLabel','Pipe Diameter in mm', 'YLabel', 'Time in sec','Title','Battery reaches target temperature','BarColor',[215,136,36]/255);

% PLOT 2: Battery coolant behavior 
plotTimeData(resultsLogs,"tempCoolBattIn",'XLabel','Time in sec','YLabel', 'Temperature in °C','Title','Battery Coolant Inlet','Legend',labelo);
plotTimeData(resultsLogs,"tempCoolBattOut",'XLabel','Time in sec','YLabel', 'Temperature in °C','Title','Battery Coolant Outlet','Legend',labelo);
plotTimeData(resultsLogs,"tempPlate",'XLabel','Time in sec','YLabel', 'Temperature in °C','Title','Plate Temperature','Legend',labelo);

% PLOT 3: exchanged heat over time
plotBarGraph(plateDiam*1000,[heatEnergies.battEnergyToPlate]','XLabel','Pipe Diameter in mm', 'YLabel', 'Energy in Wh','Title','Heat from Battery to Plate','BarColor',[215,136,36]/255);