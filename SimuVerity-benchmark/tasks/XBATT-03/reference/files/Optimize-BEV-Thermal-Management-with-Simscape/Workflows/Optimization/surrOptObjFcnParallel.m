function Vals = surrOptObjFcnParallel(P,Simulator)
%% Description:
% Objective function for the optimization of the vehicle model. The
% function retrieves the table (denoted as the input x) and distributes the
% values stored in x to the correct variables. 
% Subsequently, the function calculates the consumption of the vehicle for
% a summer and winter scenario given that the vehicle is parametrized as in x. 
% Finally, from the two consumption a total consumption is calculated. The
% function also evaluates constraints to see how quickly the battery and
% the cabin reach the desired temperature
%
% This function has been adapted to be used with Simulink Design Optimization

%% Inputs:
% P          : [7x1 Tunable]: Parameters to be updated to the model
% Simulator  : [1x1 SimulationTest]: Simulation Test object of the model

%-----------------
% Copyright 2022-2025 The MathWorks, Inc.
%-----------------

%% 1) Set up the continuous and discrete variables:
% Simulate the model.
Simulator.Parameters = P;

% Assign parameters
chiller_tube_D       = P(1).Value;
condenser_L          = P(2).Value;
pipeDiamCoolingPlate = round(P(3).Value,5);
evaporator_L         = P(4).Value;
transRatio           = round(P(5).Value,2);
heater_max_power     = P(6).Value;
ptc_max_power        = P(7).Value;

% Update Cooling plate diameter and added length
sdo.setValueInModel(Simulator.ModelName, 'pipeDiamCoolingPlate',  pipeDiamCoolingPlate);
sdo.setValueInModel(Simulator.ModelName, 'lengthAddCoolingPlate', round(2*pipeDiamCoolingPlate*12*20,5));

% Transmission Ratio
sdo.setValueInModel(Simulator.ModelName, 'transRatio',  transRatio);

% Heaters
sdo.setValueInModel(Simulator.ModelName, 'ptc_max_power',     ptc_max_power);
sdo.setValueInModel(Simulator.ModelName, 'heater_max_power',  heater_max_power);

% Chiller
setChillerDiameterSDO(chiller_tube_D); 

% Condenser and Evaporator
setCondenserLengthSDO(condenser_L);
setEvaporatorLengthSDO(evaporator_L);

%% 2) Apply and simulate summer scenario 
simInputSum  = Simulink.SimulationInput(Simulator.ModelName);
simInputSum  = setSimInputObj(simInputSum,'FixAllParam',1,'Scenario','Summer');
simInputSum.applyToModel;

% Simulate Summer Scenario
Simulator = sim(Simulator); 

% Collect results
results     = calcVehicleEnergy(Simulator.LoggedData.sscThermalManagement); 
resultsLogs = Simulator.LoggedData.logsout;

% Battery Energy / Time for Battery to Reach Target Temperature / Time for Cabin to Reach Target Temperature
energyLossSum     = results.energyBattery;
battTargetTimeSum = checkTempReq([resultsLogs.get('tempBattery').Values.Time, resultsLogs.get('tempBattery').Values.Data],[5,35]); 
cabiTargetTimeSum = checkTempReq([resultsLogs.get('tempCabin').Values.Time,   resultsLogs.get('tempCabin').Values.Data],[24,26]);  
simOutputSum      = results.simTimeEnd;

%% 3) Apply and simulate winter scenario 
simInputWin  = Simulink.SimulationInput(Simulator.ModelName);
simInputWin  = setSimInputObj(simInputWin,'FixAllParam',1,'Scenario','Winter');
simInputWin.applyToModel;

% Simulate Winter Scenario
Simulator = sim(Simulator); 

% Collect results
results     = calcVehicleEnergy(Simulator.LoggedData.sscThermalManagement); 
resultsLogs = Simulator.LoggedData.logsout; 

% Battery Energy / Time for Battery to Reach Target Temperature / Time for Cabin to Reach Target Temperature
energyLossWin     = results.energyBattery;
battTargetTimeWin = checkTempReq([resultsLogs.get('tempBattery').Values.Time, resultsLogs.get('tempBattery').Values.Data],[5,35]); 
cabiTargetTimeWin = checkTempReq([resultsLogs.get('tempCabin').Values.Time,   resultsLogs.get('tempCabin').Values.Data],[24,26]); 
simOutputWin      = results.simTimeEnd;

% Mean consumption for Urban Summer and Highway Winter (derived from sensitivity analysis)
s = [1.35, 2.83]; 

% Calculate the cost function: Combined Consumption
combLosses = energyLossSum/s(1) + energyLossWin/s(2);

% If one of the two simulation could not follow the cycle set the consumption to NaN
if (simOutputSum < 765) || (simOutputWin < 765);combLosses = NaN; end

% If the target temperature is not reached on time, set t=tmax
cabiTargetTimeWin = min(cabiTargetTimeWin,765);
battTargetTimeWin = min(battTargetTimeWin,765);
cabiTargetTimeSum = min(cabiTargetTimeSum,765);
battTargetTimeSum = min(battTargetTimeSum,765);

%% 4) Assign outputs to the optimizer
% Impose that cabin and battery are at right temperature after respectively 12 and 10 minutes
Vals.Cleq(1) = cabiTargetTimeSum - 720; 
Vals.Cleq(2) = battTargetTimeSum - 600;
Vals.Cleq(3) = cabiTargetTimeWin - 720;
Vals.Cleq(4) = battTargetTimeWin - 600;

% These are not real constraints, but assigning the consumption values
% here, enables us to access the summer and winter consumption (which would not be accessible otherwise)
Vals.Cleq(5) = -energyLossWin;
Vals.Cleq(6) = -energyLossSum;    
Vals.Cleq    = Vals.Cleq(:);

% Assign the objective
Vals.F = combLosses;
end