function simInput = setSimInputObj(simInput,vars,varargin)
%% Description: 
% This function updates a Simulation Input Object with the required
% variables. The resulting simulation Input object can be used to simulate
% the vehicle with the chosen parametrization. 

% If you want to optimize/simulate variables different than the one chosen
% in scripts such as surrOptBEV and sensitivityGlobal, you need to modify
% also this function to update those variable via the simInput object

%% Input:
% vars          : [1x7 table]          : Table containing the variables to be set
% simInput      : [1x1 SimulationInput]: Simulation Input object to the model, obtained for example as: simInput = Simulink.SimulationInput(modelName)
% varargin      : varargin             : Implements additional inputs. See section 1) for more info

%-----------------
% Copyright 2023-2025 The MathWorks, Inc.
%-----------------

%% 1) Optional Inputs for Fixed variables
% Get model name:
mdlName = simInput.ModelName;

% Parse input arguments
p = inputParser;

% These variables decide which variables will NOT be updated
addOptional(p,'FixAllParam',0);
addOptional(p,'Scenario','Summer');

% Use the parse object and create the optional variables
parse(p, varargin{:});

% Create the optional input variables
FixAllParam = p.Results.FixAllParam;
Scenario    = p.Results.Scenario;

%% 2) Change the parameters:
% Update the model parameters based on the given inputs
if FixAllParam == 0
    % Update the pipeDiameter of the cooling plate but also update the added length (which is diameter-dependent)
    pipeDiamCoolingPlate  = round(vars.pipeDiamCoolingPlate,5);
    simInput              = simInput.setVariable('pipeDiamCoolingPlate',pipeDiamCoolingPlate,'Workspace',mdlName);
    lengthAddCoolingPlate = round(2*pipeDiamCoolingPlate*12*20,5); % Aggregate equivalent length of local resistances, m  
    simInput              = simInput.setVariable('lengthAddCoolingPlate',lengthAddCoolingPlate,'Workspace',mdlName);
    
    % Update the transmission ratio
    transRatio            = round(vars.transRatio,2);
    simInput              = simInput.setVariable('transRatio',transRatio,'Workspace',mdlName);
    
    % Update the power of PTC and HEATER
    heater_max_power      = vars.heater_max_power;
    ptc_max_power         = vars.ptc_max_power;
    simInput              = simInput.setVariable('heater_max_power',heater_max_power,'Workspace',mdlName);
    simInput              = simInput.setVariable('ptc_max_power',ptc_max_power,'Workspace',mdlName);
    
    % Updating the chiller diameter will impact on other variables, that
    % are updated in the setChillerDiameter function
    simInput = setChillerDiameter(vars.chiller_tube_D,simInput); 
    
    % Updating the condenser and evaporator length will impact on other variables, that
    % are updated in the setCondenserLength and setEvaporatorLength functions
    simInput = setCondenserLength(vars.condenser_L, simInput);
    simInput = setEvaporatorLength(vars.evaporator_L,simInput); 
end

%% 3) Set scenario
% Set drive cycle and whether conditions
simInput = setScenario(simInput,Scenario);

end