% Code to plot simulation results from sm_wheel_loader_driveline
%% Plot Description:
%
% The plot below shows the speeds of the input and output shafts.
%
% Copyright 2017-2025 The MathWorks, Inc.

% Generate simulation results
mdl = 'sm_wheel_loader_driveline';
set_param([mdl '/Driveshaft Rear'],'popup_driveJointR','U Joint');
sim(mdl)

% Get simulation results
simlog_tUJ  = simlog_sm_wheel_loader_driveline.Revolute_Output_Shaft.Rz.w.series.time;
simlog_wUJ  = simlog_sm_wheel_loader_driveline.Revolute_Output_Shaft.Rz.w.series.values('rpm');
simlog_wIn  = simlog_sm_wheel_loader_driveline.Revolute_Gear_Driveshaft.Rz.w.series.values('rpm');
simlog_qBe  = simlog_sm_wheel_loader_driveline.Frame.Planar_Joint.Rz.q.series.values('deg');

set_param([mdl '/Driveshaft Rear'],'popup_driveJointR','CV Joint');
sim(mdl)
simlog_tCV  = simlog_sm_wheel_loader_driveline.Revolute_Output_Shaft.Rz.w.series.time;
simlog_wCV  = simlog_sm_wheel_loader_driveline.Revolute_Output_Shaft.Rz.w.series.values('rpm');


% Reuse figure if it exists, else create new figure
if ~exist('h1_sm_wheel_loader_driveline', 'var') || ...
        ~isgraphics(h1_sm_wheel_loader_driveline, 'figure')
    h1_sm_wheel_loader_driveline = figure('Name', 'sm_wheel_loader_driveline');
end
figure(h1_sm_wheel_loader_driveline)
clf(h1_sm_wheel_loader_driveline)

temp_colororder = get(gca,'defaultAxesColorOrder');

% Plot results
ah = subplot(2,1,1);
plot(simlog_tUJ, simlog_wIn, 'LineWidth', 2, 'DisplayName','Input')
hold on
plot(simlog_tUJ, simlog_wUJ,'LineWidth', 2, 'DisplayName','U Joint')
plot(simlog_tCV, simlog_wCV,'--', 'LineWidth', 2, 'DisplayName','CV Joint')
hold off
grid on
title('Shaft Speeds')
ylabel('Speed (RPM)')
legend('Location','Best');

ah = subplot(2,1,2);
plot(simlog_tUJ, simlog_qBe, 'LineWidth', 2)
title('Shaft Bend Angle (deg)')
ylabel('deg')
xlabel('Time (s)')
grid on
maxY = max(abs(get(gca,'YLim')));
set(gca,'YLim',[-1 1]*maxY)

