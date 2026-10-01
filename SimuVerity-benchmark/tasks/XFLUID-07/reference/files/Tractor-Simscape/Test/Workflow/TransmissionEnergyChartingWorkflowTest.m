classdef TransmissionEnergyChartingWorkflowTest < InitializeTestForWorkflows & matlab.unittest.TestCase
    % The test class runs the scripts and functions associated with
    % transmission energy charting workflow and verify there are no 
    % warnings or errors when files are executed.

    % For more information on verifiable class execute in MATLAB Command
    % window: web(fullfile(docroot, 'matlab/ref/matlab.unittest.qualifications.verifiable-class.html'))
    
    % Copyright 2024 The MathWorks, Inc.

    methods (Test)

        function TestEnvelopeAndRatingWorkflowMLX(test)
            %The test runs the |.mlx| file and makes sure that there are
            %no errors or warning thrown.
            test.verifyWarningFree(@()runTransmissionEnergyChartingWorkflow,...
                '''TransmissionEnergyChartingWorkflow'' |.mlx|  should execute without any warnings or errors.');

            % For more information on verifiable class execute in MATLAB Command window: web(fullfile(docroot, 'matlab/ref/matlab.unittest.qualifications.verifiable-class.html'))
        end

    end

end

function runTransmissionEnergyChartingWorkflow()
% Function runs the |.mlx| script.
TransmissionEnergyChartingWorkflow
end
