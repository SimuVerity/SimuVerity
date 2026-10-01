% Task_8_ Run the model (occlusion detection deactivated) with parameter variations and save the results
% Matlab
% The following parameters are varied
% 1. Bolus magnitude
% 2. Bolus duration
% 3. Bolus interval
% 4. Occlusion percentage
% Don't run this infront of customers 180 cases will take a long time to
% complete
clc
close all
clear
run InitializationInsulinPump
run ParameterSweep
delete(gcp("nocreate"));
% uncomment the following to run the parameter sweep
% run ParameterSweep
%% Verify whether the data format is still avaliable for the batch generation
% simOut = sim('InfusionPumpModelV7NoOccDetect','ReturnWorkspaceOutputs','on','FastRestart','on');
% t_sample = 0.01;
% time = 0:t_sample:120;
% Analy_Force = simOut.get('Result_Force');
% idx_init = find(Analy_Force(:,2)<9);
% Analy_Force(idx_init,2) = 9;
% Analy_Force(:,2) = Analy_Force(:,2)-Analy_Force(idx_init,2);
% Analy_Speed = simOut.get('Result_MotorSpeed');
% Analy_PistonSpd = Analy_Speed(:,2)/reserv_str.DriveSys.GearRatio*reserv_str.DriveSys.ScrewLead*25.4/60*1000;
% idx_sec1 = 1:5000;
% idx_sec2 = 5500:length(time);
% Input1  = Analy_Speed(idx_sec1,2)+0.05*randn(length(idx_sec1),1);
% Output1 = Analy_Force(idx_sec1,2)+0.05*randn(length(idx_sec1),1);
% Input2  = Analy_Speed(idx_sec2,2)+0.05*randn(length(idx_sec2),1);
% Output2 = Analy_Force(idx_sec2,2)+0.05*randn(length(idx_sec2),1);
% figure
% subplot(2,1,1)
% plot(time(idx_sec1),Output1,time(idx_sec2),Output2)
% xlabel('Time (sec)')
% ylabel('Force (N)')
% grid
% subplot(2,1,2)
% plot(time(idx_sec1),Input1,time(idx_sec2),Input2)
% xlabel('Time (sec)')
% ylabel('Motor Speed (RPM)')
% grid