classdef TireModelTest < matlab.unittest.TestCase
    % System level test for Tire Model block
    
    % For more information on verifiable class execute in MATLAB command
    % window: web(fullfile(docroot, 'matlab/ref/matlab.unittest.qualifications.verifiable-class.html'))

    % Copyright 2024 The MathWorks, Inc.

    properties
        model = 'TireModelTestHarness';
    end

    methods(TestMethodSetup)

        function loadModelWithTeardown(testCase)
            % This function executes before each test method runs. This
            % function loads the model and adds a teardown which is
            % executed after each test method is run.

            % Load the model
            load_system(testCase.model);

            % Close the model after each test point
            testCase.addTeardown(@()bdclose(testCase.model));
        end

    end

    methods (Test)

        function testTranslationalVelocityAndSlip(testCase)
            % The test checks for the output translational velocity and
            % slip for the set input parameters for the Tire-soil model
            % block.

            % Setup model for testing
            set_param(strcat(testCase.model,'/Normal Force'), 'constant', '1000', 'constant_unit', 'N');
            set_param(strcat(testCase.model,'/PS Constant tc'), 'constant', '1000', 'constant_unit', 'N/m^2');
            set_param(strcat(testCase.model,'/PS Constant tphi'), 'constant', '60', 'constant_unit', 'deg');
            set_param(strcat(testCase.model,'/PS Constant tk'), 'constant', '0.1', 'constant_unit', 'm');
            set_param(strcat(testCase.model,'/PS Constant tykc'), 'constant', '48', 'constant_unit', '1');
            set_param(strcat(testCase.model,'/PS Constant tykphi'), 'constant', '6067', 'constant_unit', '1');
            set_param(strcat(testCase.model,'/PS Constant tyn'), 'constant', '0.78', 'constant_unit', '1');

            % Set parameters for Angular Velocity and PS Ramp block
            slope = 6; startTime = 0.5; initialOutput = 0;
            set_param(strcat(testCase.model,'/Angular Velocity'), 'slope', num2str(slope), 'slope_unit', 'rad/s^2');
            set_param(strcat(testCase.model,'/Angular Velocity'), 'start_time', num2str(startTime), 'start_time_unit', 's');
            set_param(strcat(testCase.model,'/Angular Velocity'), 'initial_output', num2str(initialOutput), 'initial_output_unit', 'rad/s');
            set_param(strcat(testCase.model,'/PS Saturation'), 'upper_limit', '30', 'upper_limit_unit', 'rad/s');
            set_param(strcat(testCase.model,'/PS Saturation'), 'lower_limit', '-30', 'lower_limit_unit', 'rad/s');

            % Set parameters for Mass block
            set_param(strcat(testCase.model,'/Mass'), 'mass', '10', 'mass_unit', 'kg');

            % Set parameters for Translational damper block
            set_param(strcat(testCase.model,'/Translational Damper'), 'D', '1e-3', 'D_unit', 'N*s/m');

            % Set model stop time to 20 sec
            set_param(testCase.model, 'StopTime', '20');

            % Simulate the model and get simulated output value
            out = sim(testCase.model);
            actualSlipVector = out.yout{1}.Values;
            actualTranslationalVelocityVector = out.simlog.Simscape_Component.H.v.series.values('m/s');

            % Verify slip when angular velocity reaches 30 rad/s
            angularVelocity = 30;
            timeAtVelocity30 = (angularVelocity -initialOutput)/slope + startTime;
            actualSlipAt30 = actualSlipVector.Data(find(out.tout <= timeAtVelocity30, 1, 'last'));
            testCase.verifyEqual(actualSlipAt30, 0.12, 'AbsTol', 1e-2, 'RelTol', 1e-2,...
                'The Actual slip value when angular velocity reaches 30 does not match the expected slip value.');

            % Verify slip and translational velocity at t = 20 sec
            slipAtTime20 = actualSlipVector.Data(end);
            translationalVelocityAtTime20 = actualTranslationalVelocityVector(end);

            testCase.verifyEqual(slipAtTime20, 0.0582, 'AbsTol', 1e-2, 'RelTol', 1e-2,...
                'The Actual slip value at time equal to 20 sec does not match the expected slip value.');
            testCase.verifyEqual(translationalVelocityAtTime20, 14.1266, 'AbsTol', 1e-2, 'RelTol', 1e-2,...
                'The Actual translational velocity at time equal to 20 sec does not match the expected value.');
            
        end
    end

end