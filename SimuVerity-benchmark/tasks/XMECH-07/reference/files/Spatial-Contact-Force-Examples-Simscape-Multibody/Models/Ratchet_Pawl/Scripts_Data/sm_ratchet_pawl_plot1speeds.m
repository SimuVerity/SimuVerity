% Code to plot simulation results from sm_ratchet_pawl
%% Plot Description:
%
% <enter plot description here if desired>
%
% Copyright 2023-2026 The MathWorks, Inc.

% Generate simulation results if they don't exist
if ~exist('simlog_sm_ratchet_pawl', 'var')
    sim('sm_ratchet_pawl')
end

% Reuse figure if it exists, else create new figure
if ~exist('h1_sm_ratchet_pawl', 'var') || ...
        ~isgraphics(h1_sm_ratchet_pawl, 'figure')
    h1_sm_ratchet_pawl = figure('Name', 'sm_ratchet_pawl');
end
figure(h1_sm_ratchet_pawl)
clf(h1_sm_ratchet_pawl)

temp_colororder = get(gca,'defaultAxesColorOrder');

% Get simulation results
simlog_t    = simlog_sm_ratchet_pawl.Revolute_Wheel.Rz.w.series.time;
simlog_wWhl = simlog_sm_ratchet_pawl.Revolute_Wheel.Rz.w.series.values('deg/s');
simlog_wArm = simlog_sm_ratchet_pawl.Revolute_Driver_Arm.Rz.w.series.values('deg/s');

simlog_tArm = logsout_sm_ratchet_pawl.get('Arm Torque');

% Plot results
simlog_handles(1) = subplot(2, 1, 1);
plot(simlog_t, simlog_wArm,'LineWidth', 1, 'DisplayName','Arm')
hold on
plot(simlog_t, simlog_wWhl, '-', 'LineWidth', 1, 'DisplayName','Wheel')
hold off
grid on
title('Rotational Speed')
ylabel('Speed (deg/s)')
legend('Location','Best');

simlog_handles(2) = subplot(2, 1, 2);
plot(simlog_tArm.Values.Time, squeeze(simlog_tArm.Values.Data), 'LineWidth', 1)
grid on
title('Driver Arm Torque')
ylabel('Torque (N*m)')
xlabel('Time (s)')

xlabel('Time (s)')


linkaxes(simlog_handles, 'x')

% Remove temporary variables
clear simlog_t simlog_handles
clear simlog_R1i simlog_C1v temp_colororder

