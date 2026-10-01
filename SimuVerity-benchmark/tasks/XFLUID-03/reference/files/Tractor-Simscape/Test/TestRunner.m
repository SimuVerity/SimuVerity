% Test runner for Tractor Model with Simscape project
% The test runner script for this project is used to create a test suite
% that consists of test classes in the 'Test' folder. The runner runs
% the test suite and generates output.

% Copyright 2024-25 The MathWorks, Inc.

relStr = matlabRelease().Release;
disp("This is MATLAB " + relStr + ".");

topFolder = currentProject().RootFolder

%% Create test suite
% Test suite for unit test
suite = matlab.unittest.TestSuite.fromFolder(fullfile(topFolder,"Test"), 'IncludingSubfolders', true);
suite = selectIf(suite, 'Superclass', 'matlab.unittest.TestCase');

%% Create test runner
runner = matlab.unittest.TestRunner.withTextOutput(...
    'OutputDetail',matlab.unittest.Verbosity.Detailed);

%% Set up JUnit style test results
runner.addPlugin(matlab.unittest.plugins.XMLPlugin.producingJUnitFormat(...
fullfile(topFolder, "Test", "TractorModelWithSimscape_TestResults_"+relStr+".xml")));

%% MATLAB Code Coverage Report
coverageReportFolder = fullfile(topFolder, "coverage-TractorCodeCoverage" + relStr);
if ~isfolder(coverageReportFolder)
    mkdir(coverageReportFolder)
end

coverageReport = matlab.unittest.plugins.codecoverage.CoverageReport( ...
    coverageReportFolder, MainFile = "TractorCoverageReport" + relStr + ".html");

% Code Coverage Plugin
list = dir(fullfile(topFolder, '**/*.*'));
exceptions = {  'SoilTexture.m',... % Enum file for |.ssc| code
                'ImplementType.m',... % Enum file for |.ssc| code
                'ForceComputation.m' % Enum file for |.ssc| code
            };
list = list(~[list.isdir] & endsWith({list.name}, {'.m', '.mlx'}) & ~contains({list.folder},'Test') & ~startsWith({list.name}, exceptions));

fileList = arrayfun(@(x)[x.folder, filesep, x.name], list, 'UniformOutput', false);
codeCoveragePlugin = matlab.unittest.plugins.CodeCoveragePlugin.forFile(fileList, Producing = coverageReport, MetricLevel="condition");
addPlugin(runner, codeCoveragePlugin);

%% Run tests
results = run(runner, suite);
out = assertSuccess(results);
disp(out);