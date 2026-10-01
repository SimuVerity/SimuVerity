%% Description: 
% This script optimizes the model following these steps: 
% - The model will be optimized using surrogateopt
% - A chosen set of parameters will be changed during optimization
% - The aim is to change the parameters to reduce vehicle consumption
% - Vehicle consumption is defined as a combined consumption of two scenario (summer cycle and winter cycle)
% - While optimizing, it has to be ensured that the battery and the cabin reach a target temperature within a given amount of time
% This script parallelizes the optimization by using Simulink Design
% Optimization (SDO) and Parallel Computing Toolbox  
%-----------------
% Copyright 2022-2025 The MathWorks, Inc.
%-----------------

%% Inputs: Set simulation options here
clear;
numWorkers  = 8;                                                   % CHECK on your parallel settings how many workers you have available!
hasParallelToolbox = license('test', 'Distrib_Computing_Toolbox'); % Check if a license is active for parallel toolbox:

% Stop the code and output an error in case the parallel computing toolbox is not available as a license
if hasParallelToolbox==0; error('No Parallel Computing Toolbox Installed'); end

%% 1) Initialize model:
modelName = checkModel('BEV_Thermal_Management');

% Switch to the optimization folder, where the results will be stored
cd(fileparts(which(mfilename)))

% Create the string to use to save the model
saveString = [pwd filesep 'results' filesep 'surrogateoptParallel_' datestr(now,'YYmmDD_hhMM'),'.mat'];

%% 2) Specify Design Variables and their ranges
% Specify model parameters as design variables to optimize.
DesignVars = sdo.getParameterFromModel(modelName,{'chiller_tube_D','condenser_L','pipeDiamCoolingPlate','evaporator_L','transRatio'},{'heater_max_power','ptc_max_power'});

% Set the ranges for the continuous design variables
DesignVars(1).Minimum  = 0.002; % Minimum diameter chiller tube in m
DesignVars(1).Maximum  = 0.005; % Maximum diameter chiller tube in m
DesignVars(2).Minimum  = 1;     % Minimum condenser length in m
DesignVars(2).Maximum  = 1.4;   % Maximum condenser length in m 
DesignVars(3).Minimum  = 0.004; % Minimum cooling pipe (battery plate) diameter in m
DesignVars(3).Maximum  = 0.012; % Maximum cooling pipe (battery plate) diameter in m
DesignVars(4).Minimum  = 0.5;   % Minimum evaporator length in m
DesignVars(4).Maximum  = 1;     % Maximum evaporator length in m
DesignVars(5).Minimum  = 5;     % Minimum gearbox ratio
DesignVars(5).Maximum  = 11;    % Maximum gearbox ratio

% Set the ranges for the discrete design variables
DesignVars(6).ValueSet = 4000:250:5500;   % Battery heater power in W
DesignVars(7).ValueSet = 2000:500:3500;   % PTC heater power in W

%% 3) Simulation Set up
% Specify model signals to log during model simulation.
Simulator = sdo.SimulationTest(modelName);

% Setup simulator
Simulator = setup(Simulator, 'FastRestart', 'on');

% Add Cleanup tasks to restore any changes after completion/termination.
% Use an anonymous function with no arguments that calls the restore method.
SimulatorCleanup = onCleanup(@() restore(Simulator));

% Check if model has unsaved changes. If this is the case, turn off Fast Restart and reload the model workspace
if bdIsDirty(modelName)   % Reset model workspace to default values
    set_param(modelName, 'FastRestart', 'off');
    save_system(modelName);
end

% Specify optimization options.
Options                                      = sdo.OptimizeOptions;
Options.Method                               = 'surrogateopt';
Options.MethodOptions.CheckpointFile         = saveString; 
Options.OptimizedModel                       = Simulator;
Options.UseParallel                          = 1;                 % change it to 0 when debugging
[~,Options.ParallelFileDependencies]         = sdo.getModelDependencies(modelName);
Options.MethodOptions.PlotFcn                = @surrogateoptplot; % changed this from default to take in Lorenzo's changes
Options.MethodOptions.MinSurrogatePoints     = 25;                % Number of points used to create the first surrogate model
Options.MethodOptions.MaxFunctionEvaluations = 120;               % Maximum number of function calls used by surrogateopt
Options.MethodOptions.Display                = "iter";            % Display iterations over the simulation time

% Define the optimization function as an anonymous function call
optimfcn = @(P) surrOptObjFcnParallel(P,Simulator);

%% 4) Optimize
% Check if a parallel pool is already active
pool = gcp('nocreate');

if Options.UseParallel == 1
    if isempty(pool)
        % If no pool is active, start a new parallel pool
        disp('No parallel pool active. Starting a new parallel pool...');
        parpool(numWorkers); % Start a new parallel pool with default settings
    else
        % If a pool is already active, display the number of workers
        fprintf('A parallel pool is already active with %d workers.\n', pool.NumWorkers);
    end
end

% Call sdo.optimize with the objective function handle, parameters to optimize, and options.
[Optimized_DesignVars,Info] = sdo.optimize(optimfcn,DesignVars,Options);

% Set the simulation output object back to the default name:
set_param(modelName,'FastRestart','off');
set_param(modelName,'ReturnWorkspaceOutputsName','simres');

%% 5) Plot the results:
% Load the evaluated points
load(saveString);

% Design variables tested by the optimizer: 
x = CheckPointData.SurrogateSolverData.globalBest.X;

% The inequality constraints of the model
trials.Ineq = CheckPointData.SurrogateSolverData.trialData.dataStorage.response(:,2:end);
trials.X    = CheckPointData.SurrogateSolverData.trialData.dataStorage.X;

% Post process the results
postproOptim(trials,x)