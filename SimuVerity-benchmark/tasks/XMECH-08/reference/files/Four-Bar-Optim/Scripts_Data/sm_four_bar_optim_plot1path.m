% Code to plot simulation results from sm_four_bar_optim
%% Plot Description:
%
% The plot below shows the path of a pointer on the end of a four-bar
% linkage.  Varying the lengths of the bars will change the trajectory of
% this point.
%
% Copyright 2017-2025 The MathWorks, Inc.

% Generate simulation results if they don't exist
if ~exist('simlog_sm_four_bar_optim', 'var')
    simOut=sim('sm_four_bar_optim');
end

% Reuse figure if it exists, else create new figure
if ~exist('h1_sm_four_bar_optim', 'var') || ...
        ~isgraphics(h1_sm_four_bar_optim, 'figure')
    h1_sm_four_bar_optim = figure('Name', 'sm_four_bar_optim');
end
figure(h1_sm_four_bar_optim)
clf(h1_sm_four_bar_optim)

% Get simulation results
simlog_xy_pos = simOut.logsout_sm_four_bar_optim.get('xy_pos');
xy_pos_Data = simlog_xy_pos.Values.Data;
xy_pos = xy_pos_Data-min(xy_pos_Data);

% Plot results
plot(xy_pos(:,1),xy_pos(:,2),'LineWidth',1);
axis equal
title('Trajectory of Four-Bar Linkage');
grid on

% Remove temporary variables
clear simlog_t simlog_handles


