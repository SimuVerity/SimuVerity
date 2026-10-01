% Task_4_3 Test result viewing improved
% UI Simulink Test Manager/ Report Generation
% Inspect result and explain the reasoning behind the improvement
% Show the automatically generated report from the test
clc
bdclose('all')
close all
clear
sltest.testmanager.view
tfObj = sltest.testmanager.load('InfusionPumpTest.mldatx');
sltest.testmanager.clearResults
open('ClassifierTestResult.mldatx')