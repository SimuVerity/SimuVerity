% Code to plot simulation results from sm_tracked_vehicle_belt
%% Plot Description:
%
% The plot below shows the speed of the tread drive.
%
% Copyright 2017-2026 The MathWorks, Inc.

% Generate simulation results if they don't exist
if ~exist('simlog_sm_tracked_vehicle_belt', 'var')
    sim('sm_tracked_vehicle_belt')
end

% Reuse figure if it exists, else create new figure
if ~exist('h1_sm_tracked_vehicle_belt', 'var') || ...
        ~isgraphics(h1_sm_tracked_vehicle_belt, 'figure')
    h1_sm_tracked_vehicle_belt = figure('Name', 'sm_tracked_vehicle_belt');
end
figure(h1_sm_tracked_vehicle_belt)
clf(h1_sm_tracked_vehicle_belt)

%temp_colororder = get(gca,'defaultAxesColorOrder');

% Get simulation results
simlog_t = simlog_sm_tracked_vehicle_belt.Bushing_Vehicle.Px.p.series.time;
simlog_treadPxv = simlog_sm_tracked_vehicle_belt.Bushing_Vehicle.Px.v.series.values('m/s');
simlog_treadPyv = simlog_sm_tracked_vehicle_belt.Bushing_Vehicle.Py.v.series.values('m/s');

simlog_treadPx = simlog_sm_tracked_vehicle_belt.Bushing_Vehicle.Px.p.series.values('m');
simlog_treadPy = simlog_sm_tracked_vehicle_belt.Bushing_Vehicle.Py.p.series.values('m');

simlog_treadwr = logsout_sm_tracked_vehicle_belt.get('w_treadr');


% Plot results
simlog_handles(1) = subplot(2, 1, 1);
plot(simlog_t, sqrt(simlog_treadPxv.^2.+simlog_treadPyv.^2).*sign(simlog_treadwr.Values.Data), 'LineWidth', 1)
grid on
box on
title('Tread Speed')
xlabel('Time (s)');
ylabel('Speed (m/s)');

simlog_handles(2) = subplot(2, 1, 2);
plot(simlog_treadPx, simlog_treadPy, 'LineWidth', 1)
axis equal
text(0.05,0.95,[sprintf('%3.2f', Elapsed_Sim_Time) ' sec, ' num2str(length(tout)) ' Steps'],'Units','normalized','Color',[0.6 0.6 0.6])
grid on
box on
title('Tread Position')
xlabel('Position x (m)');
ylabel('Position y (m)');

% Remove temporary variables
clear simlog_t temp_colororder simlog_handles
clear simlog_treadPxv simlog_treadPyv simlog_treadPx simlog_treadPy
clear simlog_treadwr

