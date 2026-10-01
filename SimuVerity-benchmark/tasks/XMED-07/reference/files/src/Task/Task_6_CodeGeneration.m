% Task_6_Codegeneration
%% Open code generation report and inspect linkage to the model, requirement and different model reference
bdclose('all')
clear
run InitializationInsulinPump
close all
open('InfusionPumpSoftwareModel')
[status, msg, msgID] = mkdir('CodeGen')
cd Codegen;
slbuild('InfusionPumpSoftwareModel')
cd ../
coder.report.generate('InfusionPumpSoftwareModel');

[status, message, messageid] = rmdir('CodeGen\slprj\','s');