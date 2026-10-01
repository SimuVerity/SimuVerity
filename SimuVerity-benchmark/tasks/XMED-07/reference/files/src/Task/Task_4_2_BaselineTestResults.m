% Task_4_2 Test result viewing baseline
% UI Simulink Test Manager and Simulink
% Inspect the any of the failed test case and explain why it is failed
clc
bdclose('all')
close all
clear
run('Analy_TimeSeriesFeatureExtration');
close all
open('OcclusionDetection')
sltest.harness.open('OcclusionDetection/Occlusion1','OcclusionDetection_Harness1');
sltest.testmanager.view
tfObj = sltest.testmanager.load('InfusionPumpTest.mldatx');
sltest.testmanager.clearResults
open('HeuristicsTestResult.mldatx');