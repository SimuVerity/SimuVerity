function sm_wheel_loader_plot6cvtpowerflow(simlog)
% Function to plot flow of power in wheel loader model
%
% Copyright 2023-2025 The MathWorks, Inc.

simlog_cvt_trans = simlog.Transmission.Power_Split_Hydromech;

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


p_time    = simlog_cvt_trans.Power_Sensor1_CVT_In.Power_Sensor.P.series.time;
p1e       = simlog_cvt_trans.Power_Sensor1_CVT_In.Power_Sensor.P.series.values('kW');
p2HSIn    = simlog_cvt_trans.Power_Sensor2_HS_In.Power_Sensor.P.series.values('kW');
p3HSOut   = simlog_cvt_trans.Power_Sensor3_HS_Out.Power_Sensor.P.series.values('kW');
p4aSunIn  = simlog_cvt_trans.Power_Sensor4a_Sun1.Power_Sensor.P.series.values('kW');
p4bRingIn = simlog_cvt_trans.Power_Sensor4b_Ring1.Power_Sensor.P.series.values('kW');
p4cHRB    = simlog_cvt_trans.Power_Sensor4c_HRB.Power_Sensor.P.series.values('kW');
p5PGOut   = simlog_cvt_trans.Power_Sensor5_PGOut.Power_Sensor.P.series.values('kW');
p6CVTOut  = simlog_cvt_trans.Power_Sensor6_CVT_Out.Power_Sensor.P.series.values('kW');
p7BrkOut  = simlog_cvt_trans.Power_Sensor7_BrkOut.Power_Sensor.P.series.values('kW');
p7BrkCarr = simlog_cvt_trans.Power_Sensor7_BrkCarr.Power_Sensor.P.series.values('kW');

figure(77)
plot(p_time,p1e,'DisplayName','p1e')
hold on
plot(p_time,p2HSIn,'DisplayName','p2HSin')
plot(p_time,p3HSOut,'DisplayName','p3HSOut')
plot(p_time,p4bRingIn+p4aSunIn,'DisplayName','pG4in')
plot(p_time,p4cHRB,'DisplayName','p4cHRB')
plot(p_time,p5PGOut,'DisplayName','p5PGOut')
plot(p_time,p6CVTOut,'DisplayName','p7CVTOut')
plot(p_time,p7BrkCarr,'DisplayName','p7BrkCarr')
plot(p_time,p7BrkOut,'DisplayName','p7BrkOut')

hold off
legend('Location','Best')


