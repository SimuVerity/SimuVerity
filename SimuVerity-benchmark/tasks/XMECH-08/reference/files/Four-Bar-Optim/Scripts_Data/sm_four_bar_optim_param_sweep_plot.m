% Script to plot possible trajectories of end effector as 
% linkage lengths are varied

% Copyright 2017-2025 MathWorks, Inc.

% Create figure
if ~exist('h2_sm_four_bar_optim', 'var') || ...
        ~isgraphics(h2_sm_four_bar_optim, 'figure')
    h2_sm_four_bar_optim = figure('Name', 'sm_four_bar_optim');
end
figure(h2_sm_four_bar_optim)
clf(h2_sm_four_bar_optim)
numSims = length(simOut);
title([num2str(numSims) ' Possible Trajectories for Four-Bar Linkage'])
axis equal
grid on
hold on
box on

for i=1:length(simOut)
    xy_pos = simOut(i).logsout_sm_four_bar_optim.get('xy_pos');
    
    % Can shift trajectories such that min(x)=0, min(y)=0 
    xy_pos_shifted = xy_pos.Values.Data-min(xy_pos.Values.Data)*0;
    plot(xy_pos_shifted(:,1),xy_pos_shifted(:,2),'LineWidth',1);
end

% Center plot
sm_four_bar_optim_center_plot(gca,0.05);
