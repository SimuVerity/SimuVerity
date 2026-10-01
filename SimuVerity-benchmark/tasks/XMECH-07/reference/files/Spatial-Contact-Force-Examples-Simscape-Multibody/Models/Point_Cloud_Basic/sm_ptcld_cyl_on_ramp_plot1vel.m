% Code to plot simulation results from sm_ptcld_cyl_on_ramp
%% Plot Description:
%
% The plot below compares the vertical and horizontal speed of the
% cylinders as they roll down the ramp.
%
% Copyright 2022-2026 The MathWorks, Inc.

% Generate simulation results if they don't exist
if ~exist('simlog_sm_ptcld_cyl_on_ramp', 'var')
    sim('sm_ptcld_cyl_on_ramp')
end

% Reuse figure if it exists, else create new figure
if ~exist('h1_sm_ptcld_cyl_on_ramp', 'var') || ...
        ~isgraphics(h1_sm_ptcld_cyl_on_ramp, 'figure')
    h1_sm_ptcld_cyl_on_ramp = figure('Name', 'sm_ptcld_cyl_on_ramp');
end
figure(h1_sm_ptcld_cyl_on_ramp)
clf(h1_sm_ptcld_cyl_on_ramp)

temp_colororder = get(gca,'defaultAxesColorOrder');

% Get simulation results
simlog_t = simlog_sm_ptcld_cyl_on_ramp.Bushing_Cyl_Solid.Rz.w.series.time;
simlog_wCylSolid = simlog_sm_ptcld_cyl_on_ramp.Bushing_Cyl_Solid.Rz.w.series.values('rev/s');
simlog_wCylPtCld = simlog_sm_ptcld_cyl_on_ramp.Bushing_Cyl_Point_Cloud.Rz.w.series.values('rev/s');

simlog_vyCylSolid = simlog_sm_ptcld_cyl_on_ramp.Bushing_Cyl_Solid.Py.v.series.values('m/s');
simlog_vyCylPtCld = simlog_sm_ptcld_cyl_on_ramp.Bushing_Cyl_Point_Cloud.Py.v.series.values('m/s');


% Plot results
simlog_handles(1) = subplot(2, 1, 1);
plot(simlog_t, simlog_wCylSolid, 'LineWidth', 1)
hold on
plot(simlog_t, simlog_wCylPtCld, 'LineWidth', 1)
hold off
grid on
title('Rotational Speed')
ylabel('Speed (rev/s)')
legend({['Solid   (k='  sprintf('%2.2e',cyl.solid.ck) ' N/m)'],['Points (k=' sprintf('%2.2e',cyl.ptcld.ck) ' N/m, ' num2str(size(ptcld,1)) ' points)']},'Location','Best');

simlog_handles(2) = subplot(2, 1, 2);
plot(simlog_t, simlog_vyCylSolid, 'LineWidth', 1)
hold on
plot(simlog_t, simlog_vyCylPtCld, 'LineWidth', 1)
grid on
title('Vertical Velocity')
ylabel('Velocity (m/s)')
xlabel('Time (s)')

linkaxes(simlog_handles, 'x')

% Remove temporary variables
clear simlog_t simlog_handles
clear simlog_R1i simlog_C1v temp_colororder

