%% Script to run unit tests
% This script runs all the unit tests that are the child classes of
% matlab.unittest.TestCase in the project.
% Unit test classes are automatically detected by
% the matlab.unittest.TestSuite.fromFolder function.

% Copyright 2021-2022 The MathWorks, Inc.

RelStr = matlabRelease().Release;
disp("This is MATLAB " + RelStr + ".")

%% Create test suite

TopFolder = currentProject().RootFolder;

suite_1 = matlab.unittest.TestSuite.fromFolder( ...
  fullfile(TopFolder, "Components"), IncludingSubfolders = true);

suite_2 = matlab.unittest.TestSuite.fromFolder( ...
  fullfile(TopFolder, "HEV"), IncludingSubfolders = true);

suite_3 = matlab.unittest.TestSuite.fromFile( ...
    fullfile(TopFolder, "Test", "HEV_System_UnitTest_MQC.m"));

suite = [suite_1 suite_2 suite_3];

%% Create test runner

runner = matlab.unittest.TestRunner.withTextOutput( ...
          "OutputDetail", matlab.unittest.Verbosity.Detailed);

%% JUnit style test result

plugin = matlab.unittest.plugins.XMLPlugin.producingJUnitFormat( ...
          fullfile("Test", "TestResults_"+RelStr+".xml"));

addPlugin(runner, plugin)

%% Run tests

results = run(runner, suite);

assertSuccess(results)
