% Code to plot simulation results from sm_open_differential_testrig
%% Plot Description:
%
% The plot below shows the input shaft and axle shaft speeds. A step change
% to the load on one of the axles causes the two axles to spin at different
% speeds.
%
% Copyright 2017-2025 The MathWorks, Inc.

% Generate simulation results if they don't exist
if ~exist('simlog_sm_open_differential_testrig', 'var')
    sim('sm_open_differential_testrig')
end

% Reuse figure if it exists, else create new figure
if ~exist('h1_sm_open_differential_testrig', 'var') || ...
        ~isgraphics(h1_sm_open_differential_testrig, 'figure')
    h1_sm_open_differential_testrig = figure('Name', 'sm_open_differential_testrig');
end
figure(h1_sm_open_differential_testrig)
clf(h1_sm_open_differential_testrig)

temp_colororder = get(gca,'defaultAxesColorOrder');

% Get simulation results
simlog_t = simlog_sm_open_differential_testrig.Open_Differential.Pinion_to_Ring.Constraints.Revolute_Gear_B.Rz.w.series.time;
simlog_wIn = simlog_sm_open_differential_testrig.Open_Differential.Pinion_to_Ring.Constraints.Revolute_Gear_B.Rz.w.series.values('rpm');
simlog_wAxL = logsout_sm_open_differential_testrig.get('speed axle L');
simlog_wAxR = logsout_sm_open_differential_testrig.get('speed axle R');

% Plot results
plot(simlog_t, simlog_wIn, 'LineWidth', 1)
hold on
plot(simlog_wAxL.Values.Time, simlog_wAxL.Values.Data, 'LineWidth', 1)
plot(simlog_wAxR.Values.Time, -simlog_wAxR.Values.Data, 'LineWidth', 1)
hold off
grid on
title('Shaft Speeds')
ylabel('Speed (rpm)')
xlabel('Time (s)');
legend({'Input Shaft','Axle Left','Axle Right'},'Location','Best');

% Remove temporary variables
clear simlog_t simlog_handles temp_colororder
clear simlog_wIn simlog_wAxL simlog_wAxR 

