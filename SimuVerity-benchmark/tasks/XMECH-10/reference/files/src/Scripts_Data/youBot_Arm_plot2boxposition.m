% Code to plot simulation results from youBot_Arm
%% Plot Description:
%
% The plot below shows the 3D trajectory of the box moved by the youBot
% robotic arm.
%
% Copyright 2016-2025 The MathWorks, Inc.

% Generate simulation results if they don't exist
if ~exist('simlog_youBot_Arm', 'var')
    sim('youBot_Arm')
end

% Reuse figure if it exists, else create new figure
if ~exist('h2_youBot_Arm', 'var') || ...
        ~isgraphics(h2_youBot_Arm, 'figure')
    h2_youBot_Arm = figure('Name', 'youBot_Arm');
end
figure(h2_youBot_Arm)
clf(h2_youBot_Arm)

temp_colororder = get(gca,'defaultAxesColorOrder');

% Get simulation results
if (simlog_youBot_Arm.Arm.Environment.hasChild('Load'))
	simlog_t = simlog_youBot_Arm.Arm.Environment.Load.Box.Init_Box_6_DOF_Joint.Px.p.series.time;
	simlog_boxPx = simlog_youBot_Arm.Arm.Environment.Load.Box.Init_Box_6_DOF_Joint.Px.p.series.values('m');
	simlog_boxPy = simlog_youBot_Arm.Arm.Environment.Load.Box.Init_Box_6_DOF_Joint.Py.p.series.values('m');
	simlog_boxPz = simlog_youBot_Arm.Arm.Environment.Load.Box.Init_Box_6_DOF_Joint.Pz.p.series.values('m');
else
	simlog_t = EE_xyz.time;
	simlog_boxPx = EE_xyz.signals.values(:,1);
	simlog_boxPy = EE_xyz.signals.values(:,2);
	simlog_boxPz = EE_xyz.signals.values(:,3);
end
% Plot results
plot3(simlog_boxPx, simlog_boxPy, simlog_boxPz, 'LineWidth', 1)
grid on
box on
title('Box Trajectory')
axis square
view(gca,-131,6);
set(gca,'XTickLabel','','YTickLabel','','ZTickLabel','')

% Remove temporary variables
clear simlog_t simlog_boxPx simlog_boxPy simlog_boxPz
clear temp_colororder

