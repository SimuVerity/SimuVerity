%% Description
% Increase the length of the condenser. This will increase the power required 
% by the compressor but also increase the heat exchange surface (and
% therefore the performance of the condenser). This will ultimately impact
% on how efficiently the cabin is cooled down.
% 
% Adapting the condenser length only has an impact in the case of a summer scenario
% 
% Please Note: The evaporator pressure limits the compressor power. If the
% condenser causes a pressure drop which is too big on the evaporator side,
% this will cause the compressor to derate, which might ultimate worsen
% heat exchange. This is actually what happens in this script if we only
% vary the condenser dimensions (without adjusting the evaporator)

%-----------------
% Copyright 2023-2025 The MathWorks, Inc.
%-----------------


%% 1) Set up the model
% Open and load
clear; modelName = checkModel('BEV_Thermal_Management');

% Set up folder to store results
proj = currentProject; 
saveLabel = strrep(strrep(strrep(char(datetime),'-','_'),':','_'),' ','_');
saveString= [char(proj.RootFolder) filesep 'Workflows' filesep 'Sensitivity' filesep 'results' filesep 'sweepCondenser_',saveLabel,'.mat'];

%% 2) Change condenser length
% Variation of condenser length in m
condLength = 1:0.1:1.4;

% Cycle through the condenser length
for loopSimIn = 1:numel(condLength)

    % Show progress
    fprintf('Iteration number %d \n',loopSimIn);
    
    % Create Simulink Input object and set the scenario
    simInput = Simulink.SimulationInput(modelName);
    simInput = simInput.setPostSimFcn(@(out) postSimFcnEV(out,simInput));
    simInput = setSimInputObj(simInput,'FixAllParam',1,'Scenario','Summer');

    % Resize the evaporator length and its dimensions
    simInput = setCondenserLength(condLength(loopSimIn), simInput);    

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
% Time the cabin needs to reach the target temperature in sec
cabiTime = arrayfun(@(p) checkTempReq([p.get('tempCabin').Values.Time,p.get('tempCabin').Values.Data],[24,26]), resultsLogs);

% As a legend use the condenser length
labelo   = arrayfun(@(p) [num2str(p),' m'], condLength, 'UniformOutput', false);

% PLOT 1: Temperature behavior of the cabin
plotBarGraph(condLength,cabiTime,'XLabel','Evaporator Length in m', 'YLabel', 'Time in sec','Title','Cabin reaches target temperature','FigDim',[0,0,29.92/2,12.91],'BarColor',[215,136,36]/255);
plotTimeData(resultsLogs,"tempCabin",'XLabel','Time in sec','YLabel', 'Temperature in °C','Title','Cabin Temperature','FigDim',[0,0,29.92/2,12.91],'Legend',labelo);
if (simInput(1).getVariable('battery_T_init'))<273.15; tempCabinObj = 24; else; tempCabinObj = 26; end
plot([0, 765], [tempCabinObj, tempCabinObj], 'r--','DisplayName','Target Temp','LineWidth',2);

% PLOT 2: Pressure evaporator out and corresponding compressor command
plotTimeData(resultsLogs,"pressEvapOut",'XLabel','Time in sec','YLabel', 'Pressure in MPa','FigDim',[0,0,29.92/2,12.91],'Title','Evaporator Output Pressure','FontSize',14,'Legend',labelo);
plot([0, 788], [0.3, 0.3], 'r--','DisplayName','Target Pressure','LineWidth',2);
plotTimeData(resultsLogs,"cmdComp",'XLabel','Time in sec','YLabel', 'Compressor Command','FigDim',[0,0,29.92/2,12.91],'Title','Compressor Command (proportional to Speed)','FontSize',14,'Legend',labelo);

% PLOT 3: Compressor Consumption vs. Condenser Length AND Energy Eliminated from the cabin
consCmpr = arrayfun(@(p) p.hvac.energyCmpr, results);
plotBarGraph(condLength,consCmpr*1000,'XLabel','Condenser Length in m', 'YLabel', 'Energy in Wh','Title','Compressor Energy','FigDim',[0,0,29.92/2,12.91]);
plotBarGraph(condLength,[heatEnergies.condEnergyToAir],'XLabel','Condenser Length in m', 'YLabel', 'Energy in Wh','Title','Heat Eliminated from Cabin','FigDim',[0,0,29.92/2,12.91],'BarColor',[215,136,36]/255);
