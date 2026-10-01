function sm_wheel_loader_plot5steer(simlog_WL,logsout_str)
% Code to plot simulation results from sm_wheel_loader

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
simlog_t      = squeeze(logsout_str.Steer.p.Time);
simlog_pSteer = squeeze(logsout_str.Steer.p.Data);
simlog_fSteer = squeeze(logsout_str.Steer.force.Data);
simlog_qCha   = simlog_WL.Vehicle.Revolute_Front_Rear.Rz.q.series.values('deg');
simlog_vx     = simlog_WL.Body_to_World.Px.v.series.values('km/hr');
simlog_vy     = simlog_WL.Body_to_World.Py.v.series.values('km/hr');

simlog_vveh   = sqrt(simlog_vx.^2+simlog_vy.^2);

%% Plot results
ah(1) = subplot(2,1,1);
yyaxis left
plot(simlog_t, simlog_qCha,'LineWidth', 1,'DisplayName','Chassis Angle')
ylabel('Position (m) ')
grid on

yyaxis right
plot(simlog_t, simlog_vveh,'LineWidth', 1,'DisplayName','Vehicle Speed')
ylabel('Speed (km/h) ')
title('Actuator Positions')
legend('Location','Best');

ah(2) = subplot(2,1,2);
plot(simlog_t, simlog_fSteer,'LineWidth', 1,'DisplayName','Force')
grid on
title('Actuator Forces')
ylabel('Force (N)')
xlabel('Time (s)')

linkaxes(ah,'x')
