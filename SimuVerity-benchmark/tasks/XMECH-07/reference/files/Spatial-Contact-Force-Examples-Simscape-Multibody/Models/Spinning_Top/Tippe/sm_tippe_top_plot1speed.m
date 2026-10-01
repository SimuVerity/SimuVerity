% Code to plot simulation results from sm_tippe_top
%% Plot Description:
%
% This is a plot of the rotational speed of the top. The rotational speed
% of the top about its axis switches direction as the top flips over and
% stands on its stem. Eventually the top slows down enough that both the
% stem and the body are touching the ground, and the top is rolling in a
% circle.
%
% Copyright 2022-2026 The MathWorks, Inc.

% Generate simulation results if they don't exist
if ~exist('simlog_sm_tippe_top', 'var')
    sim('sm_tippe_top')
end

% Reuse figure if it exists, else create new figure
if ~exist('h1_sm_tippe_top', 'var') || ...
        ~isgraphics(h1_sm_tippe_top, 'figure')
    h1_sm_tippe_top = figure('Name', 'sm_tippe_top');
end
figure(h1_sm_tippe_top)
clf(h1_sm_tippe_top)

temp_colororder = get(gca,'defaultAxesColorOrder');

% Get simulation results
simlog_wTop = logsout_sm_tippe_top.get('wTop');

% Plot results
plot(simlog_wTop.Values.Time, simlog_wTop.Values.Data, 'LineWidth', 2)
grid on
title('Rotational Speed of Top')
ylabel('Speed (rev/s)')
xlabel('Time (s)')

% Remove temporary variables
clear simlog_handles
clear temp_colororder
