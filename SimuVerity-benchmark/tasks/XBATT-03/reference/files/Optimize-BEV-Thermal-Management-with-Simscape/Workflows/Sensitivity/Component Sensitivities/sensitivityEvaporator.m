%% Description
% Increase the length of the evaporator. This will increase the power required 
% by the compressor but also increase the heat exchange surface (and
% therefore the performance of the evaporator). This will ultimately impact
% on how efficiently the cabin is cooled down.
% 
% Adapting the evaporator length only has an impact in the case of a summer scenario
%-----------------
% Copyright 2022-2025 The MathWorks, Inc.
%-----------------

%% 1) Set up the model
% Open and load
clear; modelName = checkModel('BEV_Thermal_Management');

% Set up folder to store results
proj = currentProject; 
saveLabel = strrep(strrep(strrep(char(datetime),'-','_'),':','_'),' ','_');
%saveString= [char(proj.RootFolder),'\Workflows\Sensitivity\results\','sweepChiller_',saveLabel,'.mat'];
saveString= [char(proj.RootFolder) filesep 'Workflows' filesep 'Sensitivity' filesep 'results' filesep 'sweepChiller_',saveLabel,'.mat'];

%% 2) Change evaporator length
% Variation of evaporator length in m
evapLength = 0.5:0.2:1.2;

% Cycle through the evaporator length
for loopSimIn = 1:numel(evapLength)

    % Show progress
    fprintf('Iteration Number %d \n',loopSimIn);

    % Create Simulink Input object and set the scenario
    simInput = Simulink.SimulationInput(modelName);
    simInput = simInput.setPostSimFcn(@(out) postSimFcnEV(out,simInput));
    simInput = setSimInputObj(simInput,'FixAllParam',1,'Scenario','Summer');
    
    % Resize the evaporator length and its dimensions
    simInput = setEvaporatorLength(evapLength(loopSimIn),simInput);
    
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

% Create legend
labelo   = arrayfun(@(p) [num2str(p),' mm'], evapLength, 'UniformOutput', false);

% The time it takes for the battery to reach the temperature:
battTime = arrayfun(@(p) checkTempReq([p.get('tempBattery').Values.Time,p.get('tempBattery').Values.Data],[5,35]), resultsLogs);
cabiTime = arrayfun(@(p) checkTempReq([p.get('tempCabin').Values.Time,p.get('tempCabin').Values.Data],[24,26]), resultsLogs);

% PLOT 1: Cabin temperature
plotTimeData(resultsLogs,"tempCabin",'XLabel','Time in sec','YLabel', 'Temperature in °C','Title','Cabin Temperature','FigDim',[0,0,29.92/2,12.91],'FontSize',14,'Legend',labelo);
plot([0, 765], [26, 26], 'r--','DisplayName','Target Temp.','LineWidth',2);
plotBarGraph(evapLength,cabiTime,'XLabel','Evaporator Length in m', 'YLabel', 'Time in sec','Title','Cabin reaches target temperature','FigDim',[0,0,29.92/2,12.91],'BarColor',[215,136,36]/255);

% PLOT 2: Temperature behavior of the cabin and battery
plotBarGraph(evapLength,[heatEnergies.evapEnergyFromCabin],'XLabel','Evaporator Length in m', 'YLabel', 'Energy in Wh','Title','Heat Eliminated from Cabin','FigDim',[0,0,29.92/2,12.91],'BarColor',[215,136,36]/255);
consCmpr = arrayfun(@(p) p.hvac.energyCmpr, results);
plotBarGraph(evapLength,consCmpr*1000,'XLabel','Evaporator Length in m', 'YLabel', 'Energy in Wh','Title','Compressor Energy','FigDim',[0,0,29.92/2,12.91]);