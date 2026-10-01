classdef TireSoilInteractionTest < matlab.unittest.TestCase
    % System level test for Tire soil interaction block

    % For more information on verifiable class execute in MATLAB command
    % window: web(fullfile(docroot, 'matlab/ref/matlab.unittest.qualifications.verifiable-class.html'))

    % Copyright 2024 The MathWorks, Inc.

    properties
        model = 'TireSoilInteractionTestHarness';
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

        function testVelocityatHNodeAndSlip(testCase)
            % The test verifies the output velocity at node H and slip are
            % as expected.

            % import
            import Simulink.sdi.constraints.MatchesSignal
            % For more information on matches signal constraint execute in
            % MATLAB command window: 
            % web(fullfile(docroot, 'simulink/slref/simulink.sdi.constraints.matchessignal-class.html?s_tid=doc_srchtitle'))

            % Setup model for testing
            set_param(strcat(testCase.model,'/Normal Force'), 'constant', '1000', 'constant_unit', 'N');
            set_param(strcat(testCase.model,'/PS Constant tc'), 'constant', '1000', 'constant_unit', 'N/m^2');
            set_param(strcat(testCase.model,'/PS Constant tphi'), 'constant', '60', 'constant_unit', 'deg');
            set_param(strcat(testCase.model,'/PS Constant tk'), 'constant', '0.1', 'constant_unit', 'm');
            set_param(strcat(testCase.model,'/PS Constant tykc'), 'constant', '48', 'constant_unit', '1');
            set_param(strcat(testCase.model,'/PS Constant tykphi'), 'constant', '6067', 'constant_unit', '1');
            set_param(strcat(testCase.model,'/PS Constant tyn'), 'constant', '0.78', 'constant_unit', '1');

            % Set paramters for velocity block
            set_param(strcat(testCase.model,'/Velocity'), 'amplitude', '5', 'amplitude_unit', 'm/s');
            set_param(strcat(testCase.model,'/Velocity'), 'bias', '0', 'bias_unit', 'm/s');
            set_param(strcat(testCase.model,'/Velocity'), 'frequency_SI', '1/50', 'frequency_SI_unit', 'Hz');
            set_param(strcat(testCase.model,'/Velocity'), 'phase', '0', 'phase_unit', 'rad');

            % Set parameters for Mass block
            set_param(strcat(testCase.model,'/Mass'), 'mass', '10', 'mass_unit', 'kg');

            % Set parameters for Translational damper block
            set_param(strcat(testCase.model,'/Translational Damper'), 'D', '1e-3', 'D_unit', 'N*s/m');

            % Simulate the model and get simulated output value
            out = sim(testCase.model);
            actualSlip = out.yout{1}.Values;
            actualVelocityAtH = timeseries(out.simlog.Simscape_Component.H.v.series.values('m/s'), out.tout, 'Name', '');
            % timetable is recommended over timeseries.
            % For more information on timeseries execute the command in
            % MATLAB command window:
            % web(fullfile(docroot, 'matlab/ref/timeseries.html?s_tid=doc_srchtitle'))


            % Get expected velocity vector at node H
            baseline = open('baselineTireSoilInteraction.mat');

            % Verify velocity at node H
            testCase.assertThat(actualVelocityAtH, MatchesSignal(baseline.expectedVelocityAtH, 'AbsTol', 1e-2, 'RelTol', 1e-2),...
                'Actual draft force does not match the expected value.');

            % Calculate slip for the tire
            actualVelocityAtT = out.simlog.Simscape_Component.T.v.series.values('m/s');

            relativeVelocity = actualVelocityAtH.Data - actualVelocityAtT;
            vxlow = get_param(strcat(testCase.model,'/Simscape Component'), 'value@vxlow');
            velocityThreshold = get_param(strcat(testCase.model,'/Simscape Component'), 'value@v_tr_thr');
            kpumin = get_param(strcat(testCase.model,'/Simscape Component'), 'value@kpumin');
            kpumax = get_param(strcat(testCase.model,'/Simscape Component'), 'value@kpumax');

            absoluteVelocityAtT(numel(out.tout)) = zeros;
            expectedSlip(numel(out.tout)) = zeros;
            for i = 1:numel(out.tout)
                absoluteVelocityAtT(i) = testCase.smoothSaturation(abs(actualVelocityAtT(i)), vxlow, 1e8, velocityThreshold);
                expectedSlip(i) = testCase.smoothSaturation(-relativeVelocity(i)/absoluteVelocityAtT(i), kpumin, kpumax, velocityThreshold);
            end
            expectedSlip = timeseries(expectedSlip, out.tout, 'Name', '');
            % timetable is recommended over timeseries.
            % For more information on timeseries execute the command in
            % MATLAB command window:
            % web(fullfile(docroot, 'matlab/ref/timeseries.html?s_tid=doc_srchtitle'))

            % Verify Slip
            testCase.verifyThat(actualSlip, MatchesSignal(expectedSlip, 'AbsTol', 1e-2, 'RelTol', 1e-2),...
                'Actual tire slip does not match the expected slip value.');

        end

    end

    methods (Static, Access=private)

        function y= smoothSaturation(x, L, U, trw)
            % Saturate x between L and U. trw is the transition width.
            % The smoothing distorts the value of x between (L-trw/2, L+trw/2)
            % and (U-trw/2, U+trw/2).
            % The function is a quadratic that ensures continuity in y and dy/dx at
            % L-trw/2, L+trw/2, U-trw/2, and U+trw/2.

            halfWidth= 0.5*trw;
            twoL= 2*L;
            twoU= 2*U;

            if le(x, L - halfWidth)
                y= L;
            elseif lt(x, L + halfWidth)
                y= (x * (trw - twoL) + x * x) / (2 * trw) + (trw + twoL)^2 / (8 * trw);
            elseif le(x, U - halfWidth)
                y= x;
            elseif lt(x, U + halfWidth)
                y= (x * (trw + twoU) - x * x) / (2 * trw) - (trw - twoU)^2 / (8 * trw);
            else
                y= U;
            end

        end

    end

end