%% Description:
% This script will perform a sensitivity analysis on the BEV_Thermal_Management.slx by 
% varying different parameters. The parameter combinations are calculated
% with scripting from Simulink Design Optimization. If a Parallel Computing
% Toolbox is available, the user can simulate the configurations in Parallel.
% There are two sensitivity analysis: 
% - Summer: The vehicle is simulated in Summer with an Urban Cycle
% - Winter: The vehicle is simulated in Winter with a Highway Cycle
% The cycle and environmental conditions are set by the function
% setSimInputObj, which passes the Parametrization to the model as a
% Simulation Input object. 
% NB: If you want to change the variables used in the sensitivity analysis
% you also need to update setSimInputObj

%-----------------
% Copyright 2023-2025 The MathWorks, Inc.
%-----------------

%% Inputs: Set simulation options here
clear;
scenario    = 'Summer';                                            % Scenario to be simulated: 'Summer' or 'Winter'
useParallel = 1;                                                   % Use parallel pool: 1 = Yes, and 0 = No
numWorkers  = 4;                                                   % CHECK on your parallel settings how many workers you have available!
hasParallelToolbox = license('test', 'Distrib_Computing_Toolbox'); % Check if a license is active for parallel toolbox:

%% 1) Set up and load model
modelName = checkModel('BEV_Thermal_Management');

% Switch to the folder where the results will be stored
cd(fileparts(which(mfilename)));

% Create the string to use to save the model
saveString = [pwd filesep 'results' filesep 'sweep' scenario datestr(now,'YYmmDD_hhMM'),'.mat'];

%% 2) Create Sensitivity Analysis
% Table with CONTINUOUS parameter to be changed: 
% Entries in doeVarNames must have the SAME NAME as the corresponding variable in the model workspace
doeVarNames  = {'pipeDiamCoolingPlate','transRatio','chiller_tube_D','condenser_L','evaporator_L'};    
doeVarLimits = [0.004,0.012;            5,11;        0.002, 0.005;    1, 1.4;       0.5, 1.0];
doeContTable = array2table(doeVarLimits','RowNames',{'Minimum', 'Maximum'},'VariableNames',doeVarNames);

% Resulting CONTINUOUS Parameter space
contSpace = setSDOParamSpace(doeContTable,modelName);

% Table with DISCRETE parameter to be changed: 
% Entries in doeVarNames must have the SAME NAME as the corresponding variable in the model workspace
doeVarNames  = {'heater_max_power','ptc_max_power'};    
doeVarLimits = {4000:250:5500,2000:500:3500};
doeDiscTable = cell2table(doeVarLimits,'RowNames',{'Values'},'VariableNames',doeVarNames);

% Resulting DISCRETE Parameter space
discSpace = setSDOParamSpace(doeDiscTable,modelName);

% Combine CONTINUOUS AND DISCRETE space and calculate the resulting parameter space
combSpace  = combine(contSpace,discSpace);
combSpace.Options.Method = 'sequential';

% Sample the combspace multiple time to create a set of random distributed values
x  = [sdo.sample(combSpace);sdo.sample(combSpace);sdo.sample(combSpace);sdo.sample(combSpace)];

% Plot the parameter space which will be tested
sdo.scatterPlot(x);

%% 3) Create simulation Input for sensitivity analysis
% Simulation Input objects are useful if we want to use parsim
simInput(1:size(x,1)) = Simulink.SimulationInput(modelName); tic;

% Each simInput stores a different point to be tested
for loopSimIn = 1: size(x,1)
    simInput(loopSimIn) = setSimInputObj(simInput(loopSimIn),x(loopSimIn,:),'Scenario',scenario);
    inForPostSim = simInput(loopSimIn);
    simInput(loopSimIn) = simInput(loopSimIn).setPostSimFcn(@(out) postSimFcnEV(out,inForPostSim));
end

% Save the model (needed if we want to use parallel pool) 
set_param(modelName, 'FastRestart', 'on'); save_system(modelName); set_param(modelName, 'FastRestart', 'off');

%% 4) Perform sensitivity analysis
if hasParallelToolbox && useParallel; tic;
    % Get the current parallel pool without creating a new one
    pool = gcp('nocreate');
    if isempty(pool); parpool(numWorkers); end
    
    % Calling the Simulation Input with parsim
    out = parsim(simInput,'UseFastRestart','on','ShowSimulationManager','on');
else
    set_param(modelName, 'FastRestart', 'on');

    for i = 1:numel(simInput)
        sprintf('Testing Configuration Number %d', i)
        out(i) = sim(simInput(i));
    end
end

% Save the results in the folder
try save(saveString,'out','x');
catch; disp('The "results" folder does not exist and is purposely put under gitignore. Create a result folder locally'); end

%% 5) Post process the results
% Reload the results back 
simRes = load(saveString);

% Plot the results
postproSensitivity(simRes);
