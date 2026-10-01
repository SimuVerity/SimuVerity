classdef IMT_Test_Hydraulic_Lift_IP_Protect < matlab.unittest.TestCase

    properties (TestParameter)
        DemoFile = {'Hydraulic_Lift_IP_Protect'};
    end
    
    methods (TestClassSetup)
        function startGraphicsEngine(~)
            % Start the graphics engine so we don't get warning failures
            % for plots by switching to OpenGL Software.
            f = figure;
            closer = onCleanup(@()delete(f));
            surf(peaks);
        end      
        
    end
    
    methods (Test)
        function demosShouldNotWarn(testCase, DemoFile)       
            DemoFileFcn = str2func(DemoFile); % Use str2func() instead of @ because test names it the string
            testCase.verifyWarningFree(DemoFileFcn);            
        end
    end
    
%     methods (TestMethodTeardown)
%         function closeFigures(~)
%             close all
%             nntraintool close
%             
%             % Apps and things <undocumented in 19a>
%             cefWindows = matlab.internal.webwindowmanager.instance.windowList;
%             delete(cefWindows);
% 
%         end
%     end
 
end