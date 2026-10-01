function response = surrOptObjFcn(x)
%% Description:
% Objective function for the optimization of the vehicle model. The
% function retrieves the table (denoted as the input x) and distributes the
% values stored in x to the correct variables. 
% Subsequently, the function calculates the consumption of the vehicle for
% a summer and winter scenario given that the vehicle is parametrized as in x. 
% Finally, from the two consumption a total consumption is calculated. The
% function also evaluates constraints to see how quickly the battery and
% the cabin reach the desired temperature

%% Inputs:
% x          : [1x7 table]: Table containing the variables to be set. These variables have been calculated by the optimizer

%-----------------
% Copyright 2022-2025 The MathWorks, Inc.
%-----------------

%% 1) Set up the variables and correct the discrete variables:
%GbxRatio | Evap | Chill | Conds | Plate | Heat |  PTC  |   
transRatio           = x(1);
evaporator_L         = x(2);
chiller_tube_D       = x(3);
condenser_L          = x(4);
pipeDiamCoolingPlate = x(5);
heater_max_power     = x(6);
ptc_max_power        = x(7);


% Map the values of the variables
heater_max_power = interp1(1:7,4000:250:5500,heater_max_power,'nearest');
ptc_max_power    = interp1(1:4,2000:500:3500,ptc_max_power,'nearest');

% Values are saved in a table to be passed to the simulation function:
varValues = table(transRatio, evaporator_L, chiller_tube_D, condenser_L, heater_max_power, ptc_max_power, pipeDiamCoolingPlate);

%% 2) Run 1: Update the vehicle with the variables, then run Summer Scenario
% Update vehicle and then simulate
simInputSum  = Simulink.SimulationInput('BEV_Thermal_Management');
simInputSum  = setSimInputObj(simInputSum,varValues,'Scenario','Summer');
inForPostSim = simInputSum;
simInputSum  = simInputSum.setPostSimFcn(@(out) postSimFcnEV(out,inForPostSim));
simOutputSum = sim(simInputSum);

% Battery Energy in kWh/ Cooling Time Battery in sec / Cooling Time Cabin in sec
energyLossSum     = simOutputSum.results.energyBattery; 
battTargetTimeSum = checkTempReq([simOutputSum.resultsLogs.get('tempBattery').Values.Time, simOutputSum.resultsLogs.get('tempBattery').Values.Data],[5,35]); 
cabiTargetTimeSum = checkTempReq([simOutputSum.resultsLogs.get('tempCabin').Values.Time,   simOutputSum.resultsLogs.get('tempCabin').Values.Data],[24,26]);  

%% 3) Run 2: Update the vehicle with the variables, then run Winter Scenario
% Update vehicle and then simulate
simInputWin  = Simulink.SimulationInput('BEV_Thermal_Management');
simInputWin  = setSimInputObj(simInputWin,varValues,'Scenario','Winter');
inForPostSim = simInputWin;
simInputWin  = simInputWin.setPostSimFcn(@(out) postSimFcnEV(out,inForPostSim));
simOutputWin = sim(simInputWin);

% Battery Energy in kWh/ Cooling Time Battery in sec / Cooling Time Cabin in sec
energyLossWin     = simOutputWin.results.energyBattery;
battTargetTimeWin = checkTempReq([simOutputWin.resultsLogs.get('tempBattery').Values.Time, simOutputWin.resultsLogs.get('tempBattery').Values.Data],[5,35]); 
cabiTargetTimeWin = checkTempReq([simOutputWin.resultsLogs.get('tempCabin').Values.Time,   simOutputWin.resultsLogs.get('tempCabin').Values.Data],[24,26]);  

%% 4) Calculate Function Objective: Combined consumption
% Mean consumption for Urban Summer and Highway Winter
s = [1.35, 2.83]; % in kWh

% Calculate the cost function: Combined Consumption (scaled value)
combLosses = energyLossSum/s(1) + energyLossWin/s(2);

% If one of the two simulation could not follow the cycle set the consumption to NaN
if (simOutputSum.results.simTimeEnd < 765) || (simOutputWin.results.simTimeEnd < 765)
    combLosses = NaN;
end

%% 5) Assign Outputs
% If the constraints are not fulfilled, set the time to a very high value
cabiTargetTimeWin = min(cabiTargetTimeWin,765);
battTargetTimeWin = min(battTargetTimeWin,765);
cabiTargetTimeSum = min(cabiTargetTimeSum,765);
battTargetTimeSum = min(battTargetTimeSum,765);

% Impose that cabin and battery are at right temperature after respectively 12 and 10 minutes
response.Ineq(1) = cabiTargetTimeSum - 720; % If smaller than zero, the constraint is fulfilled
response.Ineq(2) = battTargetTimeSum - 600; % If smaller than zero, the constraint is fulfilled
response.Ineq(3) = cabiTargetTimeWin - 720; % If smaller than zero, the constraint is fulfilled
response.Ineq(4) = battTargetTimeWin - 600; % If smaller than zero, the constraint is fulfilled

% These are not real constraints, but assigning the consumption values
% here, enables us to access the summer and winter consumption (which would not be accessible otherwise)
response.Ineq(5) = -energyLossWin;
response.Ineq(6) = -energyLossSum;    

% String with the output:
str = 'SUMMER Cabin Time %.1f ; Battery time %.1f\nWINTER Cabin Time %.1f ; Battery time %.1f';
sprintf(str,cabiTargetTimeSum,battTargetTimeSum,cabiTargetTimeWin,battTargetTimeWin);

str = 'SUMMER CONSUMPTION:%.1f\n WINTER CONSUMPTION: %.1f';
sprintf(str,energyLossWin,energyLossSum);

% Assign the objective
response.Fval = combLosses;
end