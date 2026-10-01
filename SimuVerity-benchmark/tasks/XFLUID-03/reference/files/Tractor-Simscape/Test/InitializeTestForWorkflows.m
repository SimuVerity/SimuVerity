classdef InitializeTestForWorkflows < matlab.unittest.TestCase
    % Class to initialize the tests related to workflow.
    
    % Copyright 2024 The MathWorks, Inc.

    properties
        openfigureListBefore;
        openModelsBefore;
    end

    methods (TestClassSetup)

        function setupWorkingFolder(test)
            % Set up working folder
            import matlab.unittest.fixtures.WorkingFolderFixture;
            test.applyFixture(WorkingFolderFixture);
        end

        function suppressWarnings(test)
            % Subpress known warnings
            import matlab.unittest.fixtures.SuppressedWarningsFixture
            test.applyFixture( ...
                SuppressedWarningsFixture("MATLAB:hg:AutoSoftwareOpenGL"))
        end

    end

    methods(TestMethodSetup)

        function listOpenFigures(test)
            % List all open figures
            test.openfigureListBefore = findall(0,'Type','Figure');
        end

        function listOpenModels(test)
            % List all open simulink models
            test.openModelsBefore = get_param(Simulink.allBlockDiagrams('model'),'Name');
        end

    end

    methods(TestMethodTeardown)

        function closeOpenedFigures(test)
            % Close all figure opened during test
            figureListAfter = findall(0,'Type','Figure');
            figuresOpenedByTest = setdiff(figureListAfter, test.openfigureListBefore);
            arrayfun(@close, figuresOpenedByTest);
        end

        function closeOpenedModels(test)
            % Close all models opened during test
            openModelsAfter = get_param(Simulink.allBlockDiagrams('model'),'Name');
            modelsOpenedByTest = setdiff(openModelsAfter, test.openModelsBefore);
            close_system(modelsOpenedByTest, 0);
        end

    end

end
