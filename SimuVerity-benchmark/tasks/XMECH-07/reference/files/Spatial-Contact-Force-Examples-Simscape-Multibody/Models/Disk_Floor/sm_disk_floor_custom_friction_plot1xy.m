% Code to plot simulation results from sm_disk_floor_custom_friction
%% Plot Description:sm_disk_cyl_on_floor
%
% The plot below compares the vertical and horizontal speed of the
% cylinders as they roll down the ramp.
%
% Copyright 2022-2026 The MathWorks, Inc.

% Generate simulation results if they don't exist
if ~exist('simlog_sm_disk_floor_custom_friction', 'var')
    sim('sm_disk_floor_custom_friction')
end

% Reuse figure if it exists, else create new figure
if ~exist('h1_sm_disk_floor_custom_friction', 'var') || ...
        ~isgraphics(h1_sm_disk_floor_custom_friction, 'figure')
    h1_sm_disk_floor_custom_friction = figure('Name', 'sm_disk_floor_custom_friction');
end
figure(h1_sm_disk_floor_custom_friction)
clf(h1_sm_disk_floor_custom_friction)

temp_colororder = get(gca,'defaultAxesColorOrder');

% Get simulation results
simlog_t = simlog_sm_disk_floor_custom_friction.Bushing_Standard_Contact.Px.p.series.time;
simlog_pxDiskStan = simlog_sm_disk_floor_custom_friction.Bushing_Standard_Contact.Px.p.series.values('m');
simlog_pxDiskCust = simlog_sm_disk_floor_custom_friction.Bushing_Custom_Contact.Px.p.series.values('m');

simlog_wzDiskStan = logsout_sm_disk_floor_custom_friction.get('Disk_Standard').Values.wz;
simlog_wzDiskCust = logsout_sm_disk_floor_custom_friction.get('Disk_Custom').Values.wz;

% Plot results
simlog_handles(1) = subplot(2, 1, 1);
plot(simlog_wzDiskStan.Time, simlog_wzDiskStan.Data(:),...
    'Color',temp_colororder(3,:),'LineWidth', 1,'DisplayName','Standard Contact');
hold on
plot(simlog_wzDiskCust.Time, simlog_wzDiskCust.Data(:),...
    'Color',temp_colororder(2,:), 'LineWidth', 1,'DisplayName','Custom Contact');
hold off
grid on
title('Rotational Speed of Disks')
ylabel('Speed (rad/s)')
legend('Location','Best');

simlog_handles(2) = subplot(2, 1, 2);
plot(simlog_t, simlog_pxDiskStan,...
    'Color',temp_colororder(3,:), 'LineWidth', 1)
hold on
plot(simlog_t, simlog_pxDiskCust,...
    'Color',temp_colororder(2,:), 'LineWidth', 1)
hold off
grid on
title('Disk Position along X Axis')
ylabel('Position (m)')
xlabel('Time (s)')

linkaxes(simlog_handles, 'x')

% Remove temporary variables
clear simlog_t simlog_handles
clear simlog_R1i simlog_C1v temp_colororder

