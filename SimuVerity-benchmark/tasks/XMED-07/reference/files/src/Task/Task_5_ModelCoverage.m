% Task_5 ModelCoverage
%% Open basal test harness
% inspect the signal builder for different stimulus and run the test
bdclose('all')
close all
clear
% open('Supervisory')
% sltest.harness.open('Supervisory/BasalChart','Supervisory_Harness_Basal');

%% Automatically generate test case to achieve 100% coverage using SLDV
% Select Motor control->Design Verifier->Generate
% Tests

load_system("MotorController.slx");
tf = sltest.testmanager.TestFile('Test/InfusionPumpTest.mldatx');
ts = getTestSuites(tf); 
testcaseObj = ts(1).getTestCases;
tr = run(testcaseObj(2));
cvdata = getCoverageResults(tr);
sltest.testmanager.view;

%pause(20);
f= msgbox(["Check Motor Controller 'Extended Test Case' result";"";"Click OK to continue generating additional test cases for '100% model Coverage'"]);
uiwait(f);
testOpts = sltest.testmanager.TestOptions(testcaseObj(2)); 
newTestCaseObj = sltest.testmanager.addTestsForMissingCoverage...
   (testOpts,cvdata);
tr = run(newTestCaseObj);
sltest.testmanager.view;

%pause(30);
f1 = msgbox(["Review Model coverage. You will notice 100% code coverage";"";"Click OK to close simulink test"]);
uiwait(f1);

sltest.testmanager.clear
sltest.testmanager.clearResults
sltest.testmanager.close

[status, message, messageid] = rmdir('sldv_output\','s');
[status, message, messageid] = rmdir('slprj\','s');
[status, message, messageid] = rmdir('Work\slprj\','s');

bdclose('all')
clear;
