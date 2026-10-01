%% Run unit tests
% This script runs unit test for battery testbench

% Copyright 2023 - 2024 The MathWorks, Inc.

RelStr = matlabRelease().Release;
disp("This is MATLAB " + RelStr + ".")

TestFolder = fullfile(currentProject().RootFolder, "Tests", "UnitTests");

%% Test Suite & Runner

testPath = fullfile(TestFolder, "SandBatteryUnitTest.m");
suite = [matlab.unittest.TestSuite.fromFile( testPath)];

runner = matlab.unittest.TestRunner.withTextOutput( ...
  OutputDetail = matlab.unittest.Verbosity.Detailed );

%% JUnit Style Test Result

TestResultFile = "SandBattery_TestResults_" + RelStr + ".xml";

plugin = matlab.unittest.plugins.XMLPlugin.producingJUnitFormat( ...
  fullfile(TestFolder, TestResultFile));

addPlugin(runner, plugin)

%% Run tests
results = run(runner, suite);
assertSuccess(results)