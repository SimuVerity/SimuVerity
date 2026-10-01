%% Description
% Increasing the heater power will reduce the time required to heat up the
% battery. At the same time, the overall vehicle consumption will increase.
% This parameter study is performed in winter, as the heater is turned off
% in summer 

%-----------------
% Copyright 2022-2025 The MathWorks, Inc.
%-----------------

%% 1) Set up the model
% Open and load
clear; modelName = checkModel('BEV_Thermal_Management');

% Set up folder to store results
proj = currentProject; 
saveLabel = strrep(strrep(strrep(char(datetime),'-','_'),':','_'),' ','_');
saveString= [char(proj.RootFolder) filesep 'Workflows' filesep 'Sensitivity' filesep 'results' filesep 'sweepHeater_',saveLabel,'.mat'];

%% 2) Change Heater Power
% Variation of heater power in W
heaterPwr    = 4500:500:5500;

for loopSimIn = 1:numel(heaterPwr)
  
    % Show progress
    fprintf('Iteration Number %d \n',loopSimIn);

    % Create Simulink Input object and set the scenario
    simInput = Simulink.SimulationInput(modelName);
    simInput = simInput.setPostSimFcn(@(out) postSimFcnEV(out,simInput));
    simInput = setSimInputObj(simInput,'FixAllParam',1,'Scenario','Winter');
    
    % Resize the heater power (no other variable needs to be adapted when the heater power is changed)
    simInput = simInput.setVariable('heater_max_power',heaterPwr(loopSimIn),'Workspace',modelName);
    
    % Simulate the model using the simulation input object
    out(loopSimIn)      = sim(simInput);

    % Store also the simulation input if needed later
    in(loopSimIn)       = simInput;
end

% Get all heat energies:
heatEnergies = arrayfun(@(p) calcHeatEnergy(p.resultsLogs), out);
resultsLogs  = arrayfun(@(p) p.resultsLogs, out); 
results     =  arrayfun(@(p) p.results, out); 

% Save the results in the folder
try
    save(saveString,'out');
catch
    disp('The "results" folder does not exist and is purposely put under gitignore (to avoid loading big data to Git). Create a result folder locally')
end

%% 3) Plot Results
close all

% As a legend use the heater power in W
labelo   = arrayfun(@(p) [num2str(p),' W'], heaterPwr, 'UniformOutput', false);

% The time it takes for the battery to reach the temperature:
battTime = arrayfun(@(p) checkTempReq([p.get('tempBattery').Values.Time,p.get('tempBattery').Values.Data],[5,35]), resultsLogs);

% PLOT 1: Battery temperature and energy given to the battery
plotBarGraph(heaterPwr,-[heatEnergies.battEnergyToPlate],'XLabel','Heater Power in W', 'YLabel', 'Heat in W','Title','Heat passed to battery','BarColor',[215,136,36]/255);
plotTimeData(resultsLogs,"tempBattery",'XLabel','Time in sec','YLabel', 'Temperature in °C','Title','Battery Temperature','Legend',labelo);
plot([0, 765], [5, 5], 'r--','DisplayName','Target','LineWidth',2);

% PLOT 2: How much energy does the heater cost
plotBarGraph(heaterPwr,[results.energyBattery]*1000,'XLabel','Heater Power in W', 'YLabel', 'Energy in Wh','Title','Battery Energy');
plotBarGraph(heaterPwr,[arrayfun(@(p) p.hvac.energyHeater, results)]*1000,'XLabel','Heater Power in W', 'YLabel', 'Energy in Wh','Title','Losses from heater','BarColor',[215,136,36]/255);

% PLOT 3: When the Radiator gets activated:
plotTimeData(resultsLogs,"cmdRad",'XLabel','Time in sec','YLabel', 'Temperature in °C','Title','Radiator Bypass (Active if 1)','Legend',labelo);
plotTimeData(resultsLogs,"tempCoolBattIn",'XLabel','Time in sec','YLabel', 'Temperature in °C','Title','Coolant at Battery Inlet','Legend',labelo);

% PLOT 4: Energy that is dissipated from the radiator (ideally should go to heat up the battery)
plotBarGraph(heaterPwr,[heatEnergies.radiatEnergyFromCoolant],'XLabel','Heater Power in W', 'YLabel', 'Energy in Wh','Title','Energy Dissipated in Radiator');