% Task_7_SILEquivTest
%%
clc
bdclose('all')
close all
clear
sltest.testmanager.view
tfObj = sltest.testmanager.load('InfusionPumpTest.mldatx');

load_system("MotorController.slx");
tf = sltest.testmanager.TestFile('Test/InfusionPumpTest.mldatx');
ts = getTestSuites(tf); 
testcaseObj = ts(5).getTestCases;
tr = run(testcaseObj(1));
sltest.testmanager.view;

f= msgbox(["Check Motor Controller Equivalent Criteria Result";"";"Click OK to close simulink test"]);
uiwait(f);


sltest.testmanager.clear
sltest.testmanager.clearResults
sltest.testmanager.close
[status, message, messageid] = rmdir('CodeGen\slprj\','s');

clear;