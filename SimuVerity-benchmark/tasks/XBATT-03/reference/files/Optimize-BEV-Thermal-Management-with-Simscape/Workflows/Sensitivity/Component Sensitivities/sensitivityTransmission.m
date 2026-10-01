%% Description
% This script increases the transmission ratio of the gearbox, which will
% change the position where the Electric Machine is loaded and ultiately
% impact on the machine losses.

%-----------------
% Copyright 2022-2025 The MathWorks, Inc.
%-----------------

%% 1) Set up the model
% Open and load
clear; modelName = checkModel('BEV_Thermal_Management');

% Set up folder to store results
proj = currentProject; 
saveLabel = strrep(strrep(strrep(char(datetime),'-','_'),':','_'),' ','_');
saveString= [char(proj.RootFolder) filesep 'Workflows' filesep 'Sensitivity' filesep 'results' filesep 'sweepGerbox_',saveLabel,'.mat'];

%% 2) Change transmission ratio
% Variation of transmission ratio (unitless)
transRatio    = 7:1:11;

for loopSimIn = 1:numel(transRatio)
    % Show progress
    fprintf('Iteration Number %d \n',loopSimIn);

    % Create Simulink Input object and set the scenario
    simInput = Simulink.SimulationInput(modelName);
    simInput = simInput.setPostSimFcn(@(out) postSimFcnEV(out,simInput));
    simInput = setSimInputObj(simInput,'FixAllParam',1,'Scenario','Winter');
    
    % Resize the transmission ratio (no other variable needs to be adapted when the heater power is changed)
    simInput = simInput.setVariable('transRatio',transRatio(loopSimIn),'Workspace',modelName);

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

% Overview of Torque and Speed
labelo   = arrayfun(@(p) ['i=',num2str(p)], transRatio, 'UniformOutput', false);
plotTimeData(resultsLogs,"trqEM",'YLabel', 'Torque in Nm','Title','Machine Torque','Legend',labelo);
plotTimeData(resultsLogs,"speedEM",'YLabel', 'Speed in rad/s','Title','Machine Speed','Legend',labelo);

% Losses at the Motor, Battery and HVAC
plotBarGraph(transRatio,[results.energyLossEM],'XLabel','Ratio', 'YLabel', 'Energy in Wh','Title','Machine Losses','BarColor',[215,136,36]/255);
plotBarGraph(transRatio,[results.energyBattery]*1000,'XLabel','Ratio', 'YLabel', 'Energy in Wh','Title','Battery Losses');
