%% Run unit tests
% This script runs unit tests and generates a test result summary in XML
% and a MATLAB code coverage report in HTML.

% Copyright 2022 The MathWorks, Inc.

RelStr = matlabRelease().Release;
disp("This is MATLAB " + RelStr + ".")

TargetName = "Vehicle1D_Component";

TopFolder = fullfile(currentProject().RootFolder, "Components", "Vehicle1D");

%% Test suite

suite = matlab.unittest.TestSuite.fromFile( ...
  fullfile(TopFolder, "Test", "Vehicle1D_Component_UnitTest_MQC.m"));

%% Test runner

runner = matlab.unittest.TestRunner.withTextOutput( ...
            OutputDetail = matlab.unittest.Verbosity.Detailed );

%% JUnit Style Test Result

% Test result file is created. Don't check its existance.
TestResultFile = "TestResults_" + RelStr + ".xml";

plugin = matlab.unittest.plugins.XMLPlugin.producingJUnitFormat( ...
            fullfile(TopFolder, "Test", TestResultFile));

addPlugin(runner, plugin)

%% MATLAB Code Coverage Report

CoverageReportFolder = fullfile(TopFolder, "coverage" + RelStr);
if not(isfolder(CoverageReportFolder))
  mkdir(CoverageReportFolder)
end

CoverageReportFile = RelStr + "_" + TargetName + ".html";

coverageReport = matlab.unittest.plugins.codecoverage.CoverageReport( ...
                  CoverageReportFolder, ...
                  MainFile = CoverageReportFile );

plugin = matlab.unittest.plugins.CodeCoveragePlugin.forFile( ...
  [ ...
    fullfile(TopFolder, "Harness", "Vehicle1D_Component_harness_setup.m"), ...
    fullfile(TopFolder, "Test", "Vehicle1D_Component_UnitTest_MQC.m"), ...
    fullfile(TopFolder, "TestCases", "Vehicle1D_Component_testcase_Brake.mlx"), ...
    fullfile(TopFolder, "TestCases", "Vehicle1D_Component_testcase_Coastdown.mlx"), ...
    fullfile(TopFolder, "TestCases", "Vehicle1D_Component_testcase_Constant.mlx"), ...
    fullfile(TopFolder, "Utility", "Vehicle1D_Component_plotResults.m"), ...
    fullfile(TopFolder, "Utility", "Vehicle1D_Component_resetHarnessModel.m"), ...
    fullfile(TopFolder, "Vehicle1D_refsub_Basic_params.m")], ...
  Producing = coverageReport );

addPlugin(runner, plugin)

%%

results = run(runner, suite);

assertSuccess(results)
