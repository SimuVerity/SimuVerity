function postproSensitivity(simRes)
%% Description: 
% This function plots the results obtained with the script
% sensitivityGlobal. You can use the function to analyze the
% sensitivities and gain a better understanding on the vehicle design

%% Input:
% simRes        : [struct]          : Struct containing the results of the sensitivity analysis (see sensitivityGlobal.m)

%-----------------
% Copyright 2023-2025 The MathWorks, Inc.
%-----------------

%% 1) Filter out configurations that failed
% In the Thermal Management Model there is a stop condition in case the
% vehicle cannot follow the drive cycle. In this case, the simulation will
% be stopped. This section checks whether there is any configuration that
% did not simulate the drive cycle until the end (e.g. until time = 765 s)

% The final time of each simulation
timeCycle = arrayfun(@(p) p.results.simTimeEnd, simRes.out);

% Find the configurations that did not simulate until the end...
idDel = timeCycle<765;

% ... If there are any, delete them
if ~isempty(idDel); sprintf('The number of failed configuration is %d',numel(idDel));simRes.out(idDel)= []; end

%% 2) Scatter Plot
% Build the set of variables that was actually used in the simulation inputs
paramLabels = {'pipeDiamCoolingPlate','transRatio','chiller_tube_D','condenser_L','evaporator_L','heater_max_power','ptc_max_power'};
graphLabels = {'Plate Pipe','Gearbox Ratio','Chiller Tube','Cond. Length','Evap. Length','Heater Power','PTC Power'};
refstruct   = simRes.out(1).simInput;
varIds      = cellfun(@(p) find(ismember({refstruct.Variables.Name}, p)),paramLabels);

% Collect the variables used for the simulations 
vars = zeros(numel(simRes.out),numel(paramLabels));
for i =1:size(vars,1)
    vars(i,:) =  [simRes.out(i).simInput.Variables(varIds).Value];
end

x = array2table(vars,'VariableNames',paramLabels);
consBatt = [simRes.out.results.energyBattery]';
battTime = arrayfun(@(p) checkTempReq([p.resultsLogs.get('tempBattery').Values.Time,p.resultsLogs.get('tempBattery').Values.Data],[5,35]), simRes.out);
cabiTime = arrayfun(@(p) checkTempReq([p.resultsLogs.get('tempCabin').Values.Time,p.resultsLogs.get('tempCabin').Values.Data],[24,26]), simRes.out);

% Set the cabin Time to the maximum value for the configuration that did
% not pass. This is needed because the tornado plot does not support NaN
cabiTime(isnan(cabiTime)) = 765;

% The scatter function needs a table 
y = array2table([consBatt,battTime',cabiTime'], 'VariableNames', {'Consumption','Battery Time','Cabin Time'});

% Scatter Plot to view what the correlations are:
tiledlayout(1, 1, 'Padding', 'none', 'TileSpacing', 'none');
sdo.scatterPlot(x,y);

%% 3) Tornado Plots
% Specify options for statistical analysis
opts               = sdo.AnalyzeOptions;
opts.Method        = 'Correlation';        %{'Correlation','StandardizedRegression'};
opts.MethodOptions = {'Linear', 'Ranked'};

% Call sdo.analyze with the parameters and requirements, to determine which parameters most influence the requirements.
sensitivity = sdo.analyze(x,y,opts);

% Plot the effect on different variables
plotTornado(sensitivity,'Title','Impact on Consumption','BarLabels',graphLabels,'FigDim',[0,0,25.96/2,12.91],'FontSize',14);
adjustMargins(3.4, 1.5, 0.2, 0.7); % Left, Bottom, Right, Top Margins in cm
plotTornado(sensitivity,'Title','Impact on Battery Time','Objective',2,'BarLabels',graphLabels,'FigDim',[0,0,25.96/2,12.91],'FontSize',14);
adjustMargins(3.4, 1.5, 0.2, 0.7); % Left, Bottom, Right, Top Margins in cm
plotTornado(sensitivity,'Title','Impact on Cabin Time','Objective',3,'BarLabels',graphLabels);
end