function sm_wheel_loader_plot4linkage(simlog_lnk)
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
simlog_t      = simlog_lnk.Linkage.Lift.p.Time;
simlog_pLift  = squeeze(simlog_lnk.Linkage.Lift.p.Data);
simlog_fLift  = squeeze(simlog_lnk.Linkage.Lift.force.Data);
simlog_pTilt  = squeeze(simlog_lnk.Linkage.Tilt.p.Data);
simlog_fTilt  = squeeze(simlog_lnk.Linkage.Tilt.force.Data);

%% Plot results
ah(1) = subplot(2,1,1);
plot(simlog_t, simlog_pLift,'LineWidth', 1,'DisplayName','Lift')
hold on
plot(simlog_t, simlog_pTilt,'LineWidth', 1,'DisplayName','Tilt')
hold off
grid on
title('Actuator Positions')
ylabel('Position (m) ')
legend('Location','Best');
ah(2) = subplot(2,1,2);

plot(simlog_t, smoothdata(simlog_fLift),'LineWidth', 1,'DisplayName','Lift (filtered)')
hold on
plot(simlog_t, simlog_fTilt,'LineWidth', 1,'DisplayName','Tilt')
hold off
grid on
title('Actuator Forces')
ylabel('Force (N)')
xlabel('Time (s)')
legend('Location','Best');

linkaxes(ah,'x')
%% Remove temporary variables
