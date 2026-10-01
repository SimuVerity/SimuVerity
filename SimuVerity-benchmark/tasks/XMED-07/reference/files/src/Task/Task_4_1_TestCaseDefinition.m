% Task_4_1 Test case definition
% UI Simulink Test Manager
% key elements with UI:
% 1. How the test cases are authored
% 2. How the iterations are authored
% 3. How the test cases are linked to requirement
% 4. How the test cases are linked to test harnesses
% 5. How to run the test cases (the fault detection one takes longer time to simulate presenter could use presimulated result later)
clc
bdclose('all')
clear
close all
clear
sltest.testmanager.view
tfObj = sltest.testmanager.load('InfusionPumpTest.mldatx');
sltest.testmanager.clearResults