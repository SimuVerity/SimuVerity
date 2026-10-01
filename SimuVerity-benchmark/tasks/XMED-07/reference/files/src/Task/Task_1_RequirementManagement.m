% Task_1 RequirementManagement
%% Identify unmapped elements
clc
bdclose('all')
close all
clear
run InitializationInsulinPump
open('InfusionPumpSoftwareModel')
winopen('Syringe Infusion Pump Delivery Logic Requirement.docx')
rmi('highlightModel', 'InfusionPumpSoftwareModel')
%% Report for top level model
%Test_Sequence_Control_WebView = slwebview('InfusionPumpSoftwareModel','FollowModelReference','on'); %Remember to reopen with IE. This function doesn't work with default browser is other than IE
rmi('report', 'InfusionPumpSoftwareModel');
%% Report for supervisory
open('Supervisory')
rmi('report', 'Supervisory');