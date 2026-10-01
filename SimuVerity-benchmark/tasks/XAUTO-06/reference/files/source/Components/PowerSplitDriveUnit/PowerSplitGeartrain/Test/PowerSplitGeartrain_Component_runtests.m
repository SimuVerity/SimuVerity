%% Run unit tests
% This script runs unit tests and generates a test result summary in XML
% and a MATLAB code coverage report in HTML.

% Copyright 2022 The MathWorks, Inc.

RelStr = matlabRelease().Release;
disp("This is MATLAB " + RelStr + ".")

TargetName = "PowerSplitGeartrain_Component";

TopFolder = fullfile(currentProject().RootFolder, ...
  "Components", "PowerSplitDriveUnit", "PowerSplitGeartrain");

%% Test suite

suite = matlab.unittest.TestSuite.fromFile( ...
  fullfile(TopFolder, "Test", "PowerSplitGeartrain_Component_UnitTest_MQC.m"));

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
    fullfile(TopFolder, "Harness", "PowerSplitGeartrain_Component_harness_setup.m"), ...
    fullfile(TopFolder, "Test", "PowerSplitGeartrain_Component_UnitTest_MQC.m"), ...
    fullfile(TopFolder, "TestCases", "PowerSplitGeartrain_Component_testcase_Constant.mlx"), ...
    fullfile(TopFolder, "TestCases", "PowerSplitGeartrain_Component_testcase_Engine.mlx"), ...
    fullfile(TopFolder, "TestCases", "PowerSplitGeartrain_Component_testcase_MG1.mlx"), ...
    fullfile(TopFolder, "TestCases", "PowerSplitGeartrain_Component_testcase_MG2.mlx"), ...
    fullfile(TopFolder, "TestCases", "PowerSplitGeartrain_Component_testcase_VehSpd.mlx"), ...
    fullfile(TopFolder, "Utility", "PowerSplitGeartrain_Component_plotResults.m"), ...
    fullfile(TopFolder, "PowerSplitGeartrain_refsub_Basic_params.m")], ...
  Producing = coverageReport );

addPlugin(runner, plugin)

%%

results = run(runner, suite);

assertSuccess(results)
