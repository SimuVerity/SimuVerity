classdef ModelSimulationUnitTest < matlab.unittest.TestCase
    % This MATLAB unit test is used to run the Simulink models for the
    % project. The test verifies that models simulate without any errors or 
    % warnings. 

    % Copyright 2024-25 The MathWorks, Inc.

    methods (Test)

        function TractorEnergyComputation(testCase)
            % Test for the TractorEnergyComputation model

            % Load system and add teardown
            modelname = "TractorEnergyComputation";
            load_system(modelname)
            testCase.addTeardown(@()close_system(modelname, 0));

            % Simulate model
            sim(modelname);
        end

        function TractorTransmissionTradeOff(testCase)
            % Test for the TractorEnergyComputation model

            % Load system and add teardown
            modelname = "TractorTransmissionTradeOff";
            load_system(modelname)
            testCase.addTeardown(@()close_system(modelname, 0));

            % Simulate model
            sim(modelname);
        end

    end

end