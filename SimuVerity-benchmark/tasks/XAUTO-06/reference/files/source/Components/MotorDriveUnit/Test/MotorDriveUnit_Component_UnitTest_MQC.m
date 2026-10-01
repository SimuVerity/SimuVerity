classdef MotorDriveUnit_Component_UnitTest_MQC < matlab.unittest.TestCase
% Class implementation of unit test
%
% These are tests to achieve the Minimum Quality Criteria (MQC).
% MQC is achieved when all runnables (models, scripts, functions) run
% without any erros.
%
% You can run this test by opening in MATLAB Editor and clicking
% Run Tests button or Run Current Test button.
% You can also run this test using test runner (*_runtests.m)
% which can not only run tests but also generates summary and
% measures code coverage report.

% Copyright 2021-2023 The MathWorks, Inc.

methods (Test)

%% Component's top folder

function MQC_run_Basic_params(~)
  close all
  bdclose all
  MotorDriveUnit_refsub_Basic_params
  close all
  bdclose all
end

%% Component Harness folder

function MQC_run_harness_model_with_Basic_refsub(~)
  close all
  bdclose all
  mdl = "MotorDriveUnit_Component_harness_model";
  load_system(mdl)
  MotorDriveUnit_refsub_Basic_params
  set_param(mdl+"/Motor Drive Unit", ...
    ReferencedSubsystem = "MotorDriveUnit_refsub_Basic")
  simIn = Simulink.SimulationInput(mdl);
  simIn = setModelParameter(simIn, StopTime="100");
  sim(simIn);
  close all
  bdclose all
end

function MQC_run_setup(~)
  close all
  bdclose all
  MotorDriveUnit_Component_harness_params
  close all
  bdclose all
end

%% Component TestCases folder

function MQC_run_testcase_Constant(~)
  close all
  bdclose all
  MotorDriveUnit_Component_testcase_Constant
  close all
  bdclose all
end

function MQC_run_testcase_Drive(~)
  close all
  bdclose all
  MotorDriveUnit_Component_testcase_Drive
  close all
  bdclose all
end

end  % methods (Test)
end  % classdef
