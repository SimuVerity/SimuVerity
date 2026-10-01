classdef HydrostaticCVTSystem < matlab.unittest.TestCase
    % System level test for HydrostaticCVT sub-system reference

    % For more information on verifiable class execute in MATLAB Command
    % window: web(fullfile(docroot, 'matlab/ref/matlab.unittest.qualifications.verifiable-class.html'))

    % Copyright 2024 The MathWorks, Inc.

    properties
        model = 'HydrostaticCVTTestHarness';
        simIn;
    end

    properties(TestParameter)
        % Use TestParameter If you need to run the same test method for
        % different inputs or scenarios. In this case, this test runs the
        % hydrostatic CVT test harness with different inputs.
        scenarios = {   struct('inputType','velocitySource', 'displacement', 60, 'w', 81.2535, 'T', 8.5173),...
                        struct('inputType','velocitySource', 'displacement', -10, 'w', -13.3529, 'T', -1.3983),...
                        struct('inputType','torqueSource', 'displacement', 60, 'w', 72.6692, 'T', 7.6108),...
                        struct('inputType','torqueSource', 'displacement', -10, 'w', -422.8852, 'T', -44.2848)};
    end

    methods(TestMethodSetup)

        function loadModelWithTeardown(testCase)
            % This function executes before each test method runs. This
            % function loads the model and adds a teardown which is
            % executed after each test method is run.

            % Load the model
            load_system(testCase.model);

            % Create a Simulink.SimulationInput object for the model
            testCase.simIn = Simulink.SimulationInput(testCase.model);

            % Close the model after each test point
            testCase.addTeardown(@()bdclose(testCase.model));
        end

    end

    methods(Test)

        function testOutputSpeedAndTorque(testCase, scenarios)
            % The test check if the output speed and torque at front and
            % rear is as expected.

            % Set input displacement for Hydrostatic CVT and log values
            testCase.log(1, sprintf('Prime mover input: %s', scenarios.inputType));
            testCase.log(1, sprintf('CVT displacement: %d', scenarios.displacement));
            testCase.simIn = testCase.simIn.setBlockParameter(strcat(testCase.model,'/Displacement'),'constant',num2str(scenarios.displacement));

            % Set the input source for Hydrostatic CVT
            testCase.setSourceForCVT(scenarios.inputType);

            % Simulate the model
            out = sim(testCase.simIn);

            % Verify output 'Angular velocity' and 'Torque'
            wActual = max(abs(out.yout{1}.Values.Rear_Motor.w__rpm_.Data)) * scenarios.displacement/abs(scenarios.displacement);
            TActual = max(abs(out.yout{1}.Values.Rear_Motor.trq__N_m_.Data)) * scenarios.displacement/abs(scenarios.displacement);
            testCase.verifyEqual(wActual, scenarios.w, 'AbsTol', 1e-2, 'RelTol', 1e-2, '''Angular velocity'' is not equal to the expected value.');
            testCase.verifyEqual(TActual, scenarios.T, 'AbsTol', 1e-2, 'RelTol', 1e-2, '''Torque'' is not equal to the expected value.')

        end

    end

    methods(Access=private)

        function setSourceForCVT(testCase, source)
            % The function is used to set the input source to the system
            % and set the appropriate unit to the associated constant
            % block.

            switch source

                case 'velocitySource'

                    testCase.simIn = testCase.simIn.setBlockParameter(strcat(testCase.model,'/Ideal Angular Velocity Source'),'commented', 'off');
                    testCase.simIn = testCase.simIn.setBlockParameter(strcat(testCase.model,'/Ideal Torque Source'),'commented', 'on');

                    % Set paramters for 'PS Ramp' block
                    testCase.simIn = testCase.simIn.setBlockParameter(strcat(testCase.model,'/PS Ramp'),'slope', '200');
                    testCase.simIn = testCase.simIn.setBlockParameter(strcat(testCase.model,'/PS Ramp'),'slope_unit', 'rpm/s');
                    testCase.simIn = testCase.simIn.setBlockParameter(strcat(testCase.model,'/PS Ramp'),'initial_output', '0');
                    testCase.simIn = testCase.simIn.setBlockParameter(strcat(testCase.model,'/PS Ramp'),'initial_output_unit', 'rpm');

                    % Set paramters for 'PS Saturation' block
                    testCase.simIn = testCase.simIn.setBlockParameter(strcat(testCase.model,'/PS Saturation'),'upper_limit', '500');
                    testCase.simIn = testCase.simIn.setBlockParameter(strcat(testCase.model,'/PS Saturation'),'upper_limit_unit', 'rpm');
                    testCase.simIn = testCase.simIn.setBlockParameter(strcat(testCase.model,'/PS Saturation'),'lower_limit', '0');
                    testCase.simIn = testCase.simIn.setBlockParameter(strcat(testCase.model,'/PS Saturation'),'lower_limit_unit', 'rpm');

                case 'torqueSource'

                    testCase.simIn = testCase.simIn.setBlockParameter(strcat(testCase.model,'/Ideal Angular Velocity Source'),'commented', 'on');
                    testCase.simIn = testCase.simIn.setBlockParameter(strcat(testCase.model,'/Ideal Torque Source'),'commented', 'off');

                    % Set paramters for 'PS Ramp' block
                    testCase.simIn = testCase.simIn.setBlockParameter(strcat(testCase.model,'/PS Ramp'),'slope', '0.5');
                    testCase.simIn = testCase.simIn.setBlockParameter(strcat(testCase.model,'/PS Ramp'),'slope_unit', 'N*m/s');
                    testCase.simIn = testCase.simIn.setBlockParameter(strcat(testCase.model,'/PS Ramp'),'initial_output', '0');
                    testCase.simIn = testCase.simIn.setBlockParameter(strcat(testCase.model,'/PS Ramp'),'initial_output_unit', 'N*m');

                    % Set paramters for 'PS Saturation' block
                    testCase.simIn = testCase.simIn.setBlockParameter(strcat(testCase.model,'/PS Saturation'),'upper_limit', '3');
                    testCase.simIn = testCase.simIn.setBlockParameter(strcat(testCase.model,'/PS Saturation'),'upper_limit_unit', 'N*m');
                    testCase.simIn = testCase.simIn.setBlockParameter(strcat(testCase.model,'/PS Saturation'),'lower_limit', '0');
                    testCase.simIn = testCase.simIn.setBlockParameter(strcat(testCase.model,'/PS Saturation'),'lower_limit_unit', 'N*m');

            end

        end

    end

end
