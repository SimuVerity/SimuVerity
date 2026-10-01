function ssc_hydromech_power_split_cvt_plot1whlspd(simlog_veh, tire_radius)
% Code to plot simulation results from ssc_hydromech_power_split_cvt

% Copyright 2023-2025 The MathWorks, Inc.

figString = ['h1_' mfilename];
% Only create a figure if no figure exists
figExist = 0;
fig_hExist = evalin('base',['exist(''' figString ''')']);
if (fig_hExist)
    figExist = evalin('base',['ishandle(' figString ') && strcmp(get(' figString ', ''type''), ''figure'')']);
end
if ~figExist
    fig_h = figure('Name',figString);
    assignin('base',figString,fig_h);
else
    fig_h = evalin('base',figString);
end
figure(fig_h)
clf(fig_h)

%% Get simulation results
simlog_veh_orig = simlog_veh;
if(hasChild(simlog_veh,'CVT'))
    simlog_veh_orig = simlog_veh;
    simlog_veh = simlog_veh.Vehicle.Simscape;
end
simlog_t   = simlog_veh.Vehicle.Tires_and_Body.Tire_FL.A.w.series.time;
simlog_vLF = simlog_veh.Vehicle.Tires_and_Body.Tire_FL.A.w.series.values('rad/s')*tire_radius*3.6;
simlog_vRF = simlog_veh.Vehicle.Tires_and_Body.Tire_FR.A.w.series.values('rad/s')*tire_radius*3.6;
simlog_vLR = simlog_veh.Vehicle.Tires_and_Body.Tire_RL.A.w.series.values('rad/s')*tire_radius*3.6;
simlog_vRR = simlog_veh.Vehicle.Tires_and_Body.Tire_RR.A.w.series.values('rad/s')*tire_radius*3.6;
simlog_vVeh = simlog_veh.Vehicle.Tires_and_Body.Vehicle_Body.v.series.values('km/hr');

if(hasChild(simlog_veh_orig,'CVT'))
    %simlog_veh_orig = simlog_veh;
    simlog_veh = simlog_veh_orig.CVT.Simscape;
end

simlog_ratio_t = simlog_veh.Power_Sensor1_Engine_Out.Power_Sensor.R.w.series.time;
simlog_wCVTIn = simlog_veh.Power_Sensor1_Engine_Out.Power_Sensor.R.w.series.values('rpm');
simlog_wCVTOut = simlog_veh.Power_Sensor2_CVT_Out.Power_Sensor.R.w.series.values('rpm');

simlog_ratio = simlog_wCVTOut./simlog_wCVTIn;

%% Plot results
tmpclr = colororder(gca);

ah(1) = subplot(2,1,1);
plot(simlog_t, simlog_vVeh,'k-.','LineWidth', 1,'DisplayName','Chassis')
hold on
plot(simlog_t, simlog_vLF,'LineWidth', 1,'Color',tmpclr(1,:),'DisplayName','LF')
plot(simlog_t, simlog_vRF,'--','LineWidth', 1,'Color',tmpclr(2,:),'DisplayName','RF')
plot(simlog_t, simlog_vLR,'LineWidth', 1,'Color',tmpclr(3,:),'DisplayName','LR')
plot(simlog_t, simlog_vRR,'--','LineWidth', 1,'Color',tmpclr(4,:),'DisplayName','RR')
%hold off
grid on
title('Vehicle Wheel Speeds (km/h)')
ylabel('Speed (km/h)')
legend('Location','Best');

ah(2) = subplot(2,1,2);
plot(simlog_ratio_t, simlog_ratio,'LineWidth', 1)
title('CVT Ratio (wOut/wIn)')
ylabel('Ratio (wOut/wIn)')
grid on

xlabel('Time (s)');

%% Remove temporary variables
