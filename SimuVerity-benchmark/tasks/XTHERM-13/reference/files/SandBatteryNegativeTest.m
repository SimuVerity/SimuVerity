classdef SandBatteryNegativeTest < matlab.unittest.TestCase
    %% Negative tests
    % Copyright 2024 The MathWorks, Inc.
    properties
        MdlName = 'SandBatteryTestHarness';
        BlkPath
    end

    properties(TestParameter)
        paramName = {'numCoilX','numCoilX','numCoilY','numCoilY',...
            'cellRefT','coilWidthHeater','coilDepthHeater','nturnsHeater',...
            'nturnsHeater','heaterTubeDia','heaterTimeconst','heaterRes',...
            'heaterEmissivity','heaterMaxT','coilWidthCooler','coilDepthHeater',...
            'nturnsCooler','nturnsCooler','pipeHydraulicDia','sandDensity',...
            'sandThCond','sandSpHeat','sandInitT','filTemp'};
        paramValue = {'-1','1.5','-1','1.5',...
            '-1','-1','-1','-1',...
            '1.5','-1','-1','-1',...
            '-1','-1','-1','-1',...
            '-1','1.5','-1','-1',...
            '-1','-1','-1','-1'};
    end
    methods(TestClassSetup)
        function setup(testCase)

            testCase.assumeTrue(false, 'Test disabled until Issues are resolved!');

            testCase.BlkPath = [testCase.MdlName,'/sandBattery/Sand TES'] ;
            % Load the Model
            load_system(testCase.MdlName)
            testCase.addTeardown(@()close_system(testCase.MdlName, 0));
            set_param(testCase.MdlName, 'StopTime', '0.1')
        end
    end
    methods (Test, ParameterCombination='sequential')

        function testNegative(testCase,paramName,paramValue)

            % Simulate the harness model
            tempParameters = {'cellRefT','heaterMaxT','sandInitT','filTemp'};
            if(ismember(tempParameters,paramName))
                set_param(testCase.BlkPath,[paramName,'_unit'],'K')
            end
            set_param(testCase.BlkPath,paramName,paramValue)
            testCase.verifyError(@()sim(testCase.MdlName),...
                'physmod:simscape:engine:sli:compilation:CompilationError',['Failed to verify: ',paramName,' = ',paramValue]);

        end

    end

end  % classdef
