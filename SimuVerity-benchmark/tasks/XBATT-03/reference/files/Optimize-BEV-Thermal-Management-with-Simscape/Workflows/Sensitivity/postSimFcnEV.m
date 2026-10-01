function updatedOut = postSimFcnEV(out,simInput)
%% Description: 
% Postsim function for the simulation Input object of the parsim command.
% This function uses the out variable from the model to calculate the
% consumption of the vehicle subsystems
%% Inputs:
% out      : The output struct from the model: out = sim(simInput)
% simInput : Simulation input object
%% Author: Leopold Steiner, 09.09.2024

% Analyze the Simscape results and derive the consumption of the single subsystems
results     = calcVehicleEnergy(out.sscThermalManagement,'ReducedStructure','Yes');

% Store the Simulink logged signal in a separate variable
resultsLogs = out.logsout;

% Assign results back (they will be assigned to the simulation input)
updatedOut.results     = results;
updatedOut.resultsLogs = resultsLogs;
updatedOut.simInput    = simInput;
end