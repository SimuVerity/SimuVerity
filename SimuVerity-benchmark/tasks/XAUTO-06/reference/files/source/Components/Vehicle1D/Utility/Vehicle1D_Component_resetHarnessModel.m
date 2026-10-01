function Vehicle1D_Component_resetHarnessModel()
%% Resets harness model
% This sets simulation stop time and input block parameters to default settings.
% This is called from the Callback Button block in the harness model.

% Copyright 2022 The MathWorks, Inc.

mdl = "Vehicle1D_Component_harness_model";

disp("Resetting the model: " + mdl)

if not(bdIsLoaded(mdl))
  load_system(mdl)
end

% Reset block parameters and initial values
Vehicle1D_Component_harness_setup

simIn = Simulink.SimulationInput(mdl);

% Simulaton stop time
simIn = setModelParameter(simIn, StopTime = "100");

simIn = setBlockParameter(simIn, mdl+"/Brake force", Time="70");
simIn = setBlockParameter(simIn, mdl+"/Brake force", Before="0");
simIn = setBlockParameter(simIn, mdl+"/Brake force", After="500");

simIn = setBlockParameter(simIn, mdl+"/Road grade", Time="50");
simIn = setBlockParameter(simIn, mdl+"/Road grade", Before="-5");
simIn = setBlockParameter(simIn, mdl+"/Road grade", After="0");

simIn = setBlockParameter(simIn, mdl+"/Axle torque", Time="20");
simIn = setBlockParameter(simIn, mdl+"/Axle torque", Before="500");
simIn = setBlockParameter(simIn, mdl+"/Axle torque", After="0");

applyToModel(simIn)

end  % function
