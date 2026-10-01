classdef HEV_System_UnitTest_MQC < matlab.unittest.TestCase
% Class implementation of unit test for Minimum Quality Criteria
%
% These are tests to achieve the Minimum Quality Criteria (MQC).
% MQC is achieved when all runnables (models, scripts, functions) run
% without any errors.
%
% You can run this test by opening in MATLAB Editor and clicking
% Run Tests button or Run Current Test button.
% You can also run this test using test runner (*_runtests.m)
% which can not only run tests but also generates summary and
% generates code coverage report.

% Copyright 2021-2022 The MathWorks, Inc.

methods (Test)

%% Top Folder

function MQC_run_main_script(~)
  close all
  bdclose all
  HEVProject_main_script
  close all
  bdclose all
end

end  % methods (Test)
end  % classdef
