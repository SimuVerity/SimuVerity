% Test Runner for Battery Cooling Plate Design with Simscape 

% Copyright 2025 - 2026 The MathWorks, Inc.

relstr = matlabRelease().Release;
disp("This MATLAB Release: " + relstr)

prjRoot = currentProject().RootFolder;

%% Suite and Runner

BTMSsuite = matlab.unittest.TestSuite.fromFile(fullfile(prjRoot, "Tests", "BatteryThermalManagementSystemMQC.m"));
suite = BTMSsuite;
runner = matlab.unittest.TestRunner.withTextOutput( ...
  OutputDetail = matlab.unittest.Verbosity.Detailed);

%% JUnit Style Test Result

plugin = matlab.unittest.plugins.XMLPlugin.producingJUnitFormat( ...
  fullfile(prjRoot, "Tests", ("TestResultsModelScripts_" + relstr + ".xml")));

addPlugin(runner, plugin)

%% Code Coverage Report Plugin
coverageReportFolder = fullfile(prjRoot, "Tests", ("CodeCoverage_" + relstr));
if ~isfolder(coverageReportFolder)
  mkdir(coverageReportFolder)
end
coverageReport = matlab.unittest.plugins.codecoverage.CoverageReport(coverageReportFolder, MainFile = "BTMSCoverage_" + relstr + ".html" );

%% Code Coverage Plugin
list1 = dir(fullfile(prjRoot, "Scripts"));
list1 = list1(~[list1.isdir] & endsWith({list1.name}, {'.m', '.mlx'}));

fileList = arrayfun(@(x)[x.folder, filesep, x.name], list1, 'UniformOutput', false);
codeCoveragePlugin = matlab.unittest.plugins.CodeCoveragePlugin.forFile(fileList, Producing = coverageReport );
addPlugin(runner, codeCoveragePlugin);

%% Run tests
results = run(runner, suite);
out = assertSuccess(results);
disp(out);
