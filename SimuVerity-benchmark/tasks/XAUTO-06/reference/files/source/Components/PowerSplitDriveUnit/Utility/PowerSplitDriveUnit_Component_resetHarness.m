function PowerSplitDriveUnit_Component_resetHarness()
%% Reset harness model
% This sets simulation stop time and input block parameters to default settings.
% This is called from the Callback Button block in the harness model.

% Copyright 2022 The MathWorks, Inc.

mdl = "PowerSplitDriveUnit_Component_harness_model";

disp("Resetting the model: " + mdl)

if not(bdIsLoaded(mdl))
  load_system(mdl)
end

% Reset block parameters and initial values
PowerSplitDriveUnit_Component_harness_setup

simIn = Simulink.SimulationInput(mdl);

% Simulaton stop time
simIn = setModelParameter(simIn, StopTime = "100");

simIn = setBlockParameter(simIn, mdl+"/Road grade", dataPoints="[0 1 0; 2 3 0]");
simIn = setBlockParameter(simIn, mdl+"/Road grade", deltaT="0.1");

simIn = setBlockParameter(simIn, mdl+"/Brake force", dataPoints="[0 1 0; 2 3 0]");
simIn = setBlockParameter(simIn, mdl+"/Brake force", deltaT="0.1");

simIn = setBlockParameter(simIn, mdl+"/MG2 torque command", dataPoints="[0 20 50; 51 100 40]");
simIn = setBlockParameter(simIn, mdl+"/MG2 torque command", deltaT="0.1");

simIn = setBlockParameter(simIn, mdl+"/MG1 torque command", dataPoints="[0 60 0; 61 100 -10]");
simIn = setBlockParameter(simIn, mdl+"/MG1 torque command", deltaT="0.1");

simIn = setBlockParameter(simIn, mdl+"/Engine torque command", dataPoints="[0 40 0; 41 100 50]");
simIn = setBlockParameter(simIn, mdl+"/Engine torque command", deltaT="0.1");

applyToModel(simIn)

end  % function
