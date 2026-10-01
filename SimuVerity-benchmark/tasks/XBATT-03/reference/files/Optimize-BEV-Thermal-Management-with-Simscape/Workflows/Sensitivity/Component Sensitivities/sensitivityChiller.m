%% Description
% This script increases the chiller diameter which should promote heat
% exchange between the coolant and the refrigerant. At the same time, a
% bigger diameter will cause more losses
% 
% The Default Scenario loaded by the BEV parameter is a HWFET and Summer.
% It does not make sense to test this scenario in winter as the chiller
% will not be used

%-----------------
% Copyright 2022-2025 The MathWorks, Inc.
%-----------------

%% 1) Set up the model
% Open and load
clear; modelName = checkModel('BEV_Thermal_Management');

% Set up folder to store results
proj = currentProject; 
saveLabel = strrep(strrep(strrep(char(datetime),'-','_'),':','_'),' ','_');
saveString= [char(proj.RootFolder) filesep 'Workflows' filesep 'Sensitivity' filesep 'results' filesep 'sweepChiller_' saveLabel '.mat'];

%% 2) Change chiller diameter
% Variation of chiller diameter in m
chillerDiam     = 0.0020: 0.001: 0.0050;

for loopSimIn = 1:numel(chillerDiam)
    
    % Show progress
    fprintf('Iteration Number %d \n',loopSimIn);

    % Create Simulink Input object and set the scenario
    simInput = Simulink.SimulationInput(modelName);
    simInput = simInput.setPostSimFcn(@(out) postSimFcnEV(out,simInput));
    simInput = setSimInputObj(simInput,'FixAllParam',1,'Scenario','Summer');
    
    % Change the chiller diameter using the helper function
    simInput = setChillerDiameter(chillerDiam(loopSimIn),simInput);

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

%% 3) Show Results
close all

% As a legend use the heater power in W
labelo   = arrayfun(@(p) [num2str(p*1000),' mm'], chillerDiam, 'UniformOutput', false);

% The time it takes for the battery to reach the temperature:
battTime = arrayfun(@(p) checkTempReq([p.get('tempBattery').Values.Time,p.get('tempBattery').Values.Data],[5,35]), resultsLogs);
cabiTime = arrayfun(@(p) checkTempReq([p.get('tempCabin').Values.Time,p.get('tempCabin').Values.Data],[24,26]), resultsLogs);

% Plot the consumption of pumps and compressor
plotBarGraph(chillerDiam*1000,1000*[arrayfun(@(p) p.hvac.energyPmps, results)],'XLabel','Pipe Diameter in mm', 'YLabel', 'Energy in Wh','Title','Pump energy','BarColor',[215,136,36]/255);
plotBarGraph(chillerDiam*1000,[arrayfun(@(p) p.hvac.energyCmpr, results)]*1000,'XTicks','Yes','XLabel','Pipe Diameter in mm', 'YLabel', 'Energy in Wh','Title','Compressor Energy','FigDim',[0,0,29.92/2,12.91],'FontSize',14);

% PLOT: Battery temperature
plotTimeData(resultsLogs,"tempBattery",'XLabel','Time in sec','YLabel', 'Temperature in °C','Title','Battery Temperature','Legend',labelo);
plotBarGraph(chillerDiam*1000,battTime,'XLabel','Pipe Diameter in mm', 'YLabel', 'Time in sec','Title','Battery reaches target temperature','BarColor',[215,136,36]/255);
plotTimeData(resultsLogs,'cmdComp','XLabel','Time in sec','YLabel', 'Temperature in °C','Title','Compressor Command','Legend',labelo);

% PLOT: Cabin temperature
plotTimeData(resultsLogs,"tempCabin",'XLabel','Time in sec','YLabel', 'Temperature in °C','Title','Cabin Temperature','Legend',labelo);
plotBarGraph(chillerDiam*1000,cabiTime,'XLabel','Pipe Diameter in mm', 'YLabel', 'Time in sec','Title','Cabin reaches target temperature','BarColor',[215,136,36]/255);