classdef BatteryThermalManagementSystemMQC < initializeTestForWorkflows
    %% Class implementation of unit test

    % Copyright 2025 - 2026 The MathWorks, Inc.

    properties
        % Model and Library under test
        modelName = "BatteryTestHarness";
        libraryName string 
        sourceBlock string 
    end 

    methods (Test)

        function TestAllBatteryLibraries(testLib)
            % Find all Simulink libraries in the Libraries folder
            prjRoot = currentProject().RootFolder;
            libFiles = [dir(fullfile(prjRoot, "Components","Libraries","*.slx")); ...
                dir(fullfile(prjRoot, "Components","Libraries","*.mdl")) ];

            % Keep only files that do NOT end with "_lib.slx" or "_lib.mdl"
            isLib = endsWith({libFiles.name}, "_lib.slx") | ...
                endsWith({libFiles.name}, "_lib.mdl");

            libFiles = libFiles(~isLib);

            testLib.assertNotEmpty(libFiles, ...
                "No library files found in the 'Libraries' folder.");

            for k = 1:numel(libFiles)
                [~, baseName] = fileparts(libFiles(k).name);
                testLib.libraryName = string(baseName);

                moduleRefBlock = testLib.libraryName + "_lib/Modules/ModuleType1";

                testLib.sourceBlock = testLib.libraryName + "/" + testLib.libraryName;
                testLib.testSingleLibrary(moduleRefBlock);
            end
        end


        function TestBTMSModelForCharging(testCase)
            mdl = "PouchBatteryPack96S3PWithCustomCoolingPlateForCharging";
            load_system(mdl)
            testCase.addTeardown(@()close_system(mdl,0));
            set_param(mdl,'StopTime','120');
            testCase.verifyWarningFree(@()localSimulation(mdl), "'PouchBatteryPack96S3PWithCustomCoolingPlateForCharging' should simulate wihtout any warning or error.");
        end

        function TestThermalAnalysisBTMS(test)
            %The test runs the |.mlx| file and makes sure that there are
            %no errors or warning thrown.
            test.verifyWarningFree(@()runThermalAnalysisBTMS, "'ThermalAnalysisBatteryThermalManagementSystem Live Script'  should execute wihtout any warning or error.");
        end

    end

    methods
        function setupLibraryBlockForTesting(testLib)
            % Setup test model

            % Load battery library
            load_system(testLib.libraryName);

            % Unlock library
            set_param(testLib.libraryName, "Lock", "off");

            % Add block to the test model
            blockpath = strcat(testLib.modelName,"/",testLib.libraryName);
            add_block(testLib.sourceBlock, blockpath, 'Position', [400 110 625 326]);

            % Connect blocks
            currentSrcBlk = strcat(testLib.modelName,sprintf("/Controlled Current\nSource"));
            flowScrBlk = strcat(testLib.modelName,"/Flow Rate Source");
            flowSinkBlk = strcat(testLib.modelName,"/Reservoir Out");
            simscape.addConnection(currentSrcBlk,"head",blockpath,"+","autorouting","smart");
            simscape.addConnection(currentSrcBlk,"tail",blockpath,"-","autorouting","smart");
            simscape.addConnection(flowScrBlk,"B",blockpath,"Fluid_In","autorouting","smart");
            simscape.addConnection(flowSinkBlk,"A",blockpath,"Fluid_Out","autorouting","smart");
        end
    end

    methods (Access = private)
        function testSingleLibrary(testLib,moduleRefBlock)
            % Test that the library block simulates without any error or
            % warning for the default values.

            open_system(testLib.modelName);
            testLib.addTeardown(@()close_system(testLib.modelName, 0));
            testLib.setupLibraryBlockForTesting();

            % Set battery parameters
            %% Find battery module blocks in the module
            batteryModuleBlkPath = string(find_system(testLib.modelName, ...
                "Type", "Block", "BlockType", "SimscapeBlock", "ReferenceBlock", moduleRefBlock)); % This applies to a module library generated using buildBattery function or Battery Builder app
            numModules = numel(batteryModuleBlkPath);

            %% Set battery parameters

            % Load battery library data
            batteryLibData = load(strcat(testLib.libraryName,".mat"));
            % Get number of nodes in a module
            numNodesPerModule = batteryLibData.(testLib.libraryName).ModuleAssembly(1).Module(1).NumModels;
            % Get battery pack capacity & set current to 0.5*pack capacity
            cellCapacity = str2double(get_param(batteryModuleBlkPath(1),"BatteryCapacityCell"));
            numParallelCells = batteryLibData.(testLib.libraryName).ModuleAssembly(1).Module(1).ParallelAssembly.NumParallelCells;
            set_param(strcat(testLib.modelName,"/PS Constant"),"constant",string(-0.5.*cellCapacity*numParallelCells));

            for i = 1:numModules
                % Set battery initial targets
                set_param(batteryModuleBlkPath(i),'socCell_specify','on');
                set_param(batteryModuleBlkPath(i),'socCell_priority','High');
                set_param(batteryModuleBlkPath(i),'socCell',mat2str(repmat(0.1,1,numNodesPerModule)));
            end

            % Verify
            testLib.verifyWarningFree(@()sim(testLib.modelName),...
                ['The model with library- ''', testLib.libraryName, ''' should simulate without any errors and/or warnings.']);

            close_system(testLib.modelName,0);

        end
    end

end


function localSimulation(mdl)
sim(mdl);
end

function runThermalAnalysisBTMS()
% Function runs the |.mlx| script.
% warning("off"); % Passes in local machine, throws warning online - Identifier: "MATLAB:hg:AutoSoftwareOpenGL"
ThermalAnalysisBatteryThermalManagementSystem;

end
