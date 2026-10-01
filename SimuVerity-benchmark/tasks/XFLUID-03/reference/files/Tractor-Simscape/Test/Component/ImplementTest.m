classdef ImplementTest < matlab.unittest.TestCase
    % System level test for Implement block

    % For more information on verifiable class execute in MATLAB Command
    % window: web(fullfile(docroot, 'matlab/ref/matlab.unittest.qualifications.verifiable-class.html'))

    % Copyright 2024 The MathWorks, Inc.

    properties
        model = 'ImplementTestHarness';
    end

    properties (TestParameter)

        % Implement Type:
        % 1: Subsoiler
        % 2: MoldboardPlow
        % 3: ChiselPlow
        % 4: SweepPlow
        % 5: FieldCultivator
        implementType = {'1', '2', '3', '4', '5'};

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
        % Test methods

        function testDraftAndVerticalForceForTableBasedImplement(testCase)
            % The test verifies the Draft force and vertical force output
            % from the implement block with table-based paramterization

            % import
            import Simulink.sdi.constraints.MatchesSignal
            % For more information on matches signal constraint execute in
            % MATLAB command window: 
            % web(fullfile(docroot, 'simulink/slref/simulink.sdi.constraints.matchessignal-class.html?s_tid=doc_srchtitle'))

            % Input values for implement block parameters
            velocityVector = [-2, -1, 0, 1, 2]; %unit- m/s
            draftForceVector = [-2000, -1000, 0, 1000, 2000]; %unit- N
            verticalForceVector = [600, 300, 0, 300, 600]; %unit- N

            % Set parameter values for testing
            set_param(strcat(testCase.model,'/Simscape Component'),'parameterization','2'); 
            set_param(strcat(testCase.model,'/Simscape Component'),'velocity_vector',mat2str(velocityVector));
            set_param(strcat(testCase.model,'/Simscape Component'),'draft_vector',mat2str(draftForceVector));
            set_param(strcat(testCase.model,'/Simscape Component'),'VF_vector',mat2str(verticalForceVector));

            % Simulate the model and get simulated output value
            out = sim(testCase.model);
            actualDraftForce = out.yout{1}.Values;
            actualVerticalForce = out.yout{2}.Values;

            % Calculate expected draft force and vertical force
            velocity= out.simlog.PS_Sine_Wave.O.series.values('m/s');
            GriddedDataDraftForce = griddedInterpolant(velocityVector, draftForceVector, 'linear', 'nearest');
            expectedDraftForce = timeseries(-1*GriddedDataDraftForce(velocity), out.tout, 'Name', '');       
            GriddedDataVerticalForce = griddedInterpolant(velocityVector, verticalForceVector, 'linear', 'nearest');
            expectedVerticalForce = timeseries(GriddedDataVerticalForce(velocity), out.tout, 'Name', '');
            % timetable is recommended over timeseries.
            % For more information on timeseries execute the command in
            % MATLAB command window:
            % web(fullfile(docroot, 'matlab/ref/timeseries.html?s_tid=doc_srchtitle'))

            % Verify draft force and vertical force
            testCase.verifyThat(actualDraftForce, MatchesSignal(expectedDraftForce, 'AbsTol', 3, 'RelTol', 1e-1),...
                'Actual draft force does not match the expected value.');
            testCase.verifyThat(actualVerticalForce, MatchesSignal(expectedVerticalForce, 'AbsTol', 3, 'RelTol', 1e-1),...
                'Actual draft force does not match the expected value.');

        end

        function testDraftAndVerticalForceForASABEStandard(testCase, implementType)
            % The test verifies the Draft force and vertical force output
            % from the implement block with ASABE D497.5 standard

            % import
            import Simulink.sdi.constraints.MatchesSignal
            % For more information on matches signal constraint execute in
            % MATLAB command window: 
            % web(fullfile(docroot, 'simulink/slref/simulink.sdi.constraints.matchessignal-class.html?s_tid=doc_srchtitle'))

            % Setup model for tests
            testCase.setupModelForTesting();

            % Set parameters
            set_param(strcat(testCase.model,'/Simscape Component'),'type_implement',implementType);

            % Simulate the model and get simulated output value
            out = sim(testCase.model);
            actualDraftForce = out.yout{1}.Values;
            actualVerticalForce = out.yout{2}.Values;

            % Get paramters
            if ismember(implementType, {'1', '3', '5'})
                specificParameter = get_param(strcat(testCase.model,'/Simscape Component'),'value@number_tools');
            elseif ismember(implementType, {'2', '4'})
                specificParameter = get_param(strcat(testCase.model,'/Simscape Component'),'value@width_implement');
            end
            [machineParameterA, machineParameterB, machineParameterC] = testCase.getMachineParameters(implementType);
            tillageDepthThreshold = get_param(strcat(testCase.model,'/Simscape Component'),'value@depth_min');
            alpha = get_param(strcat(testCase.model,'/Simscape Component'),'value@rake_angle') * pi/180;
            soilTexture = out.simlog.Simscape_Component.texture_soil_input.series.values('1');

            % Calculate expected draft force and vertical force
            velocity= out.simlog.PS_Sine_Wave.O.series.values('m/s');
            absoluteVelocity = abs(velocity);
            tillageDepth = out.simlog.Tillage_depth.O.series.values('cm'); % unit- cm
            tillageDepth(tillageDepth<tillageDepthThreshold) = tillageDepthThreshold;
            [F, delta] = testCase.getParamtersForSoilTexture(soilTexture);

            expectedDraftForce(numel(velocity)) = zeros;
            expectedVerticalForce(numel(velocity)) = zeros;
            for idx = 1:numel(velocity)
                expectedDraftForce(idx) = velocity(idx)/absoluteVelocity(idx) * F(idx)*(machineParameterA + machineParameterB*absoluteVelocity(idx)*3.6 + machineParameterC*(absoluteVelocity(idx)*3.6)^2)*specificParameter*tillageDepth(idx);
                expectedVerticalForce(idx) = -expectedDraftForce(idx)*(cos(alpha + delta(idx)))/sin(alpha + delta(idx));
            end
            expectedDraftForce = timeseries(-1*expectedDraftForce', out.tout, 'Name', '');
            expectedVerticalForce = timeseries(expectedVerticalForce, out.tout, 'Name', '');
            % timetable is recommended over timeseries.
            % For more information on timeseries execute the command in
            % MATLAB command window:
            % web(fullfile(docroot, 'matlab/ref/timeseries.html?s_tid=doc_srchtitle'))

            % Remove indices below threshold velocity
            velocityThreshold = get_param(strcat(testCase.model,'/Simscape Component'),'value@velocity_thr');
            indicesBelowThreshold = find(absoluteVelocity <= 8*velocityThreshold);
            actualDraftForce = delsample(actualDraftForce, 'Index', indicesBelowThreshold);
            actualVerticalForce = delsample(actualVerticalForce, 'Index', indicesBelowThreshold);
            expectedDraftForce = delsample(expectedDraftForce, 'Index', indicesBelowThreshold);
            expectedVerticalForce = delsample(expectedVerticalForce, 'Index', indicesBelowThreshold);

            % Verify draft force and vertical force
            testCase.verifyThat(actualDraftForce, MatchesSignal(expectedDraftForce, 'AbsTol', 3, 'RelTol', 0.1),...
                'Actual draft force does not match the expected value.');
            testCase.verifyThat(actualVerticalForce, MatchesSignal(expectedVerticalForce, 'AbsTol', 3, 'RelTol', 0.1),...
                'Actual draft force does not match the expected value.');

        end

    end

    methods (Access=private)

        function setupModelForTesting(testCase)
            % The method sets up the test model for testing.

            % Setup test harness
            set_param(strcat(testCase.model,'/Simscape Component'),'parameterization','1');
            set_param(strcat(testCase.model,'/Signal Editor'),'commented','off');
            set_param(strcat(testCase.model,'/Simulink-PS Converter'),'commented','off');
            set_param(strcat(testCase.model,'/Tillage depth'),'commented','off');

            % Get port handles for the blocks
            implementBlockPortHandles = get_param(strcat(testCase.model,'/Simscape Component'), 'PortHandles');
            PSConverterBlockPortHandles = get_param(strcat(testCase.model,'/Simulink-PS Converter'), 'PortHandles');
            tillageDepthBlockPortHandles = get_param(strcat(testCase.model,'/Tillage depth'), 'PortHandles');

            % Connect port handles for the blocks
            add_line(testCase.model, PSConverterBlockPortHandles.RConn, implementBlockPortHandles.LConn(1), 'autorouting', 'on');
            add_line(testCase.model, tillageDepthBlockPortHandles.RConn, implementBlockPortHandles.LConn(2), 'autorouting', 'on');
        end

    end

    methods (Access=private, Static)

        function [machineParameterA, machineParameterB, machineParameterC] = getMachineParameters(implementType)
            % The method returns the implement parameters.

            switch implementType
                case '1'
                    machineParameterA = 226; % unit- 'N/cm/m'
                    machineParameterB = 0; % unit- 'N*s/cm/m^2';
                    machineParameterC = 1.8; % unit- 'N*s^2/cm/m^3'
                case '2'
                    machineParameterA = 652; % unit- 'N/cm/m'
                    machineParameterB = 0; % unit- 'N*s/cm/m^2';
                    machineParameterC = 5.1; % unit- 'N*s^2/cm/m^3'
                case '3'
                    machineParameterA = 91; % unit- 'N/cm/m'
                    machineParameterB = 5.4; % unit- 'N*s/cm/m^2';
                    machineParameterC = 0; % unit- 'N*s^2/cm/m^3'
                case '4'
                    machineParameterA = 390; % unit- 'N/cm/m'
                    machineParameterB = 19; % unit- 'N*s/cm/m^2';
                    machineParameterC = 0; % unit- 'N*s^2/cm/m^3'
                case '5'
                    machineParameterA = 46; % unit- 'N/cm/m'
                    machineParameterB = 2.8; % unit- 'N*s/cm/m^2';
                    machineParameterC = 0; % unit- 'N*s^2/cm/m^3'
            end

        end

        function [F, delta] = getParamtersForSoilTexture(soilTexture)
            % The method returns F and delta for input soil texture

            F(numel(soilTexture)) = zeros;
            delta(numel(soilTexture)) = zeros;

            for idx = 1:numel(soilTexture)
                switch soilTexture(idx)

                    case 1
                        F(idx) = 1;
                        delta(idx) = 6*pi/180; %unit- rad
                    case 2
                        F(idx) = 0.7;
                        delta(idx) = 10 * pi/180; %unit-rad
                    case 3
                        F(idx) = 0.45;
                        delta(idx) = 22 * pi/180; %unit- rad
                end
            end
        end

    end

end