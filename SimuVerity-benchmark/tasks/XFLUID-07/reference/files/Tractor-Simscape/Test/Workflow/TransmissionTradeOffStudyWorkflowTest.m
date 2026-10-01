classdef TransmissionTradeOffStudyWorkflowTest < InitializeTestForWorkflows & matlab.unittest.TestCase
    % The test class runs the scripts and functions associated with
    % transmission trade off study workflow and verify there are no 
    % warnings or errors when files are executed.

    % For more information on verifiable class execute in MATLAB Command
    % window: web(fullfile(docroot, 'matlab/ref/matlab.unittest.qualifications.verifiable-class.html'))
    
    % Copyright 2025 The MathWorks, Inc.

    methods (Test)

        function TestTransmissionTradeOffStudyWorkflowMLX(test)
            %The test runs the |.mlx| file and makes sure that there are
            %no errors or warning thrown.
            test.verifyWarningFree(@()runTransmissionTradeOffStudyWorkflow,...
                '''TransmissionEnergyChartingWorkflow'' |.mlx|  should execute without any warnings or errors.');

        end

    end

end

function runTransmissionTradeOffStudyWorkflow()
% Function runs the |.mlx| script.
testScript = true; %#ok<NASGU> % Required to run script with Simulation Manager set to "off".
TransmissionTradeOffStudyWorkflow
end