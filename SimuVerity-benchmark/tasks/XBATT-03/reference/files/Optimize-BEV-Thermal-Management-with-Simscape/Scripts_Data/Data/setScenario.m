function simInput = setScenario(simInput,Scenario)
%% Description
% This script sets the weather conditions and the driving cylce for the
% model
%% Inputs: 
%  simInput [1x1 simulationInput]: Simulation input object of the model
%  Scenario [char]: Char selecting the scenario, can be 'Winter', 'Summer', 'Highway with Charging Stops'

%% Outputs: 
% simInput: Updated simulation Input containing the scenario settings 

%-----------------
% Copyright 2022-2025 The MathWorks, Inc.
%-----------------

%% 1) Set scenario based on selection
switch Scenario
    case 'Winter'
        % Set all parameters for a winter simulation
        simInput = simInput.setBlockParameter([simInput.ModelName,'/Scenario/Temperature [degC]'], 'Value','-5');
        simInput = simInput.setBlockParameter([simInput.ModelName,'/Scenario/Relative Humidity'], 'Value', '0.65');
        simInput = simInput.setBlockParameter([simInput.ModelName,'/Scenario/AC On//Off'], 'Value','0');
        simInput = simInput.setBlockParameter([simInput.ModelName,'/Scenario/Sun Radiaton [W]'], 'Value','300');
        
        % Set the cycle for a Urban cycle
        cycle = driveCycleParam('HWFET');
        
        % Set the starting temperature
        startTemperature = 268.15;

        % Set the scenario popup
        set_param([simInput.ModelName,'/Scenario'],'popup','Winter');

        % Deactivate Charger Model
        set_param([simInput.ModelName,'/Charger'],'pop_charger','No Charger');

    case 'Summer'
        simInput = simInput.setBlockParameter([simInput.ModelName,'/Scenario/Temperature [degC]'], 'Value','40');
        simInput = simInput.setBlockParameter([simInput.ModelName,'/Scenario/Relative Humidity'], 'Value', '0.5');
        simInput = simInput.setBlockParameter([simInput.ModelName,'/Scenario/AC On//Off'], 'Value','1');
        simInput = simInput.setBlockParameter([simInput.ModelName,'/Scenario/Sun Radiaton [W]'], 'Value','600');
        
        % Set the cycle for a Highway cycle
        cycle = driveCycleParam('UDDS');

        % Set the starting temperature
        startTemperature = 313.15;
        
        % Set the scenario popup
        set_param([simInput.ModelName,'/Scenario'],'popup','Summer');

        % Deactivate Charger Model
        set_param([simInput.ModelName,'/Charger'],'pop_charger','No Charger');

    case 'Highway with Charging Stops' % Summer weather
        
        simInput = simInput.setBlockParameter([simInput.ModelName,'/Scenario/Temperature [degC]'], 'Value','40');
        simInput = simInput.setBlockParameter([simInput.ModelName,'/Scenario/Relative Humidity'], 'Value', '0.5');
        simInput = simInput.setBlockParameter([simInput.ModelName,'/Scenario/AC On//Off'], 'Value','1');
        simInput = simInput.setBlockParameter([simInput.ModelName,'/Scenario/Sun Radiaton [W]'], 'Value','600');
        
        % Set the cycle for a Highway cycle
        cycle = driveCycleParam('Highway with Charging Stops');

        % Set the starting temperature
        startTemperature = 313.15;
        
        % Set the scenario popup
        set_param([simInput.ModelName,'/Scenario'],'popup','Highway with Charging Stops');

        % Activate Charger Model
        set_param([simInput.ModelName,'/Charger'],'pop_charger','Charger');
end 

%% 2) Assign Output
% Update cycle and temperatures
simInput = simInput.setVariable('cycle',  cycle,'Workspace',simInput.ModelName);
simInput = simInput.setVariable('battery_T_init',  startTemperature,'Workspace',simInput.ModelName);
simInput = simInput.setVariable('plate_T_init',    startTemperature,'Workspace',simInput.ModelName);
simInput = simInput.setVariable('Emachine_T_init', startTemperature,'Workspace',simInput.ModelName);
simInput = simInput.setVariable('DCDC_T_init',     startTemperature,'Workspace',simInput.ModelName);
simInput = simInput.setVariable('coolant_T_init',  startTemperature,'Workspace',simInput.ModelName);
simInput = simInput.setVariable('cabin_T_init',    startTemperature,'Workspace',simInput.ModelName);

% Set correct model Time:
set_param(simInput.ModelName,'StopTime',num2str(max(cycle.t)));
end