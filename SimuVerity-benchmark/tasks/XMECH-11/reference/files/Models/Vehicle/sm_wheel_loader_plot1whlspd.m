function sm_wheel_loader_plot1whlspd(simlog_veh, tire_radius)
% Code to plot simulation results from sm_wheel_loader
%
% Copyright 2023-2025 The MathWorks, Inc.

%% Reuse figure if it exists, else create new figure
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
if(isempty(find(strcmp(fieldnames(simlog_veh.Wheel_Loader.Vehicle.Driveline.Driveline),'Driveline_1D'))))
    simlog_drv = simlog_veh.Wheel_Loader.Vehicle.Driveline.Driveline.Driveline_3D;
else
    simlog_drv = simlog_veh.Wheel_Loader.Vehicle.Driveline.Driveline.Driveline_1D;
end
simlog_t   = simlog_drv.Planetary_FL.Revolute_Ring_Carrier.Rz.w.series.time;
simlog_vLF = simlog_drv.Planetary_FL.Revolute_Ring_Carrier.Rz.w.series.values('rad/s')*tire_radius*3.6;
simlog_vRF = simlog_drv.Planetary_FR.Revolute_Ring_Carrier.Rz.w.series.values('rad/s')*tire_radius*3.6;
simlog_vLR = simlog_drv.Planetary_RL.Revolute_Ring_Carrier.Rz.w.series.values('rad/s')*tire_radius*3.6;
simlog_vRR = simlog_drv.Planetary_RR.Revolute_Ring_Carrier.Rz.w.series.values('rad/s')*tire_radius*3.6;

simlog_vx     = simlog_veh.Wheel_Loader.Body_to_World.Px.v.series.values('km/hr');
simlog_vy     = simlog_veh.Wheel_Loader.Body_to_World.Py.v.series.values('km/hr');

simlog_vveh   = sqrt(simlog_vx.^2+simlog_vy.^2).*sign(simlog_vLF+simlog_vRF+simlog_vLR+simlog_vRR);

tmpclr = colororder(gca);

%% Plot results
plot(simlog_t, simlog_vveh,'k-.','LineWidth', 1,'DisplayName','Chassis')
hold on
plot(simlog_t, simlog_vLF,'LineWidth', 1,'Color',tmpclr(1,:),'DisplayName','LF')
plot(simlog_t, simlog_vRF,'--','LineWidth', 1,'Color',tmpclr(2,:),'DisplayName','RF')
plot(simlog_t, simlog_vLR,'LineWidth', 1,'Color',tmpclr(3,:),'DisplayName','LR')
plot(simlog_t, simlog_vRR,'--','LineWidth', 1,'Color',tmpclr(4,:),'DisplayName','RR')
hold off
grid on
title('Vehicle Wheel Speeds')
ylabel('Speed (km/h)')
legend('Location','Best');
xlabel('Time (s)')

%% Remove temporary variables
