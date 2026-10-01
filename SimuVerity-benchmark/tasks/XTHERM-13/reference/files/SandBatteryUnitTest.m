classdef SandBatteryUnitTest < matlab.unittest.TestCase
%% Class implementation of unit test

% Copyright 2023 - 2024 The MathWorks, Inc.

%% Simple tests ... just run runnables

methods (Test)

function MQC_Harness(testCase)
  mdl = "SandBatteryTestHarness";
  % Load the Model
  load_system(mdl)
  testCase.addTeardown(@()close_system(mdl, 0));
  % Simulate the harness model
  sim(mdl);
end

end

end  % classdef