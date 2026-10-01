classdef TractorEnergyComputationScriptTest < InitializeTestForWorkflows
    % The class runs the scripts associed with the model and check if ther
    % is any error in the scripts.

    % For more information on verifiable class execute in MATLAB Command
    % window: web(fullfile(docroot, 'matlab/ref/matlab.unittest.qualifications.verifiable-class.html'))

    % Copyright 2024 The MathWorks, Inc.

    methods (Test)

        function testTractorEnergyComputationInput(testCase)
            % Test for the TractorEnergyComputationInput runs without any
            % error.

            testCase.verifyWarningFree(@()testCase.runTractorEnergyComputationInput,...
                'The script under test should run without any error or warning.');
        end

        function testImplementBlockHelp(testCase)
            % Test for the 'ImplementBlockHelp' livescript runs without any
            % error.

            testCase.verifyWarningFree(@()testCase.runImplementBlockHelp,...
                'The script under test should run without any error or warning.');
        end

        function testOpenTractorModelSimscape(testCase)
            % Test for the 'OpenTractorModelSimscape' livescript runs without any
            % error.

            % Teardown for model
            testCase.addTeardown(@()bdclose('TractorEnergyComputation'));

            evalin('base','OpenTractorModelSimscape');
        end

        function testTractorEnergyComputationModelOverview(testCase)
            % Test for the 'OpenTractorModelSimscape' livescript runs without any
            % error.

            % Teardown for model
            testCase.addTeardown(@()bdclose('TractorEnergyComputation'));

            testCase.verifyWarningFree(@()TractorEnergyComputationModelOverview,...
                'The script under test should run without any error or warning.');
        end

        function testBusElementLabelColor(testCase)
            % Test 'busElementLabelColor' changes the color for the outport
            % label.

            % Open model and add teardown
            modelname = 'TractorEnergyComputation';
            open_system(modelname);
            testCase.addTeardown(@()bdclose(modelname));

            % Verify initial condition
            busElement7 = 'TractorEnergyComputation/Tractor/Tractor Body and Powertrain/Hydrostatic CVT/Bus Element Out7';
            testCase.verifyNotEqual(get_param(busElement7, 'ForegroundColor'), '[0.1, 0.2, 0.3]',...
                'The initial ''ForegroundColor'' for busElement7 should not be as expected.');

            % Evaluate function
            open_system("TractorEnergyComputation/Tractor/Tractor Body and Powertrain/Hydrostatic CVT")
            busElementLabelColor('[0.1, 0.2, 0.3]', 1);
        end

        function testPlotEnergySankey(testCase)
            % Test check the 'plotEnergySankey' function.

            % Open model and add teardown
            modelname = 'TractorEnergyComputation';
            open_system(modelname);
            testCase.addTeardown(@()bdclose(modelname));

            % Simulate the model to get logged signals
            sim(modelname);

            % Assert if the 'logsoutTractorEnergyComputation' variable is present in workspace
            testCase.assertEqual(exist('logsoutTractorEnergyComputation','var'), 1,...
                'Test could not find variable ''logsoutTractorEnergyComputation'' in workspace.');

            % Evaluate 'plotEnergySankey' function
            testCase.verifyWarningFree(@()plotEnergySankey(logsoutTractorEnergyComputation),...
                'The script under test should run without any error or warning.');
        end
        
    end

    methods (Access=private, Static)

        function runTractorEnergyComputationInput()
            % The method runs the 'TractorEnergyComputationInput' script.
            TractorEnergyComputationInput;
        end

        function runImplementBlockHelp()
            % The method runs the 'ImplementBlockHelp' script.
            ImplementBlockHelp;
        end

    end

end
