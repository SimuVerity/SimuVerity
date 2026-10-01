% Code to plot simulation results from youBot_Arm
%% Plot Description:
%
% The plot below shows the positions of the joints in the youBot robotic
% arm.
%
% Copyright 2016-2025 The MathWorks, Inc.

% Generate simulation results if they don't exist
if ~exist('simlog_youBot_Arm', 'var')
    sim('youBot_Arm')
end

% Reuse figure if it exists, else create new figure
if ~exist('h4_youBot_Arm', 'var') || ...
        ~isgraphics(h4_youBot_Arm, 'figure')
    h4_youBot_Arm = figure('Name', 'youBot_Arm');
end
figure(h4_youBot_Arm)
clf(h4_youBot_Arm)

temp_colororder = get(gca,'defaultAxesColorOrder');

% Get simulation results
simlog_joint_pos = logsout_youBot_Arm.get('joint_pos');

% Plot results
% Plot only revolute joint angles if this is a spline test
if (max(simlog_joint_pos.Values.Time)>3.4)
    simlog_handles(1) = subplot(2, 1, 1);
end
plot(simlog_joint_pos.Values.Time, simlog_joint_pos.Values.Data(:,1:4)*180/pi, 'LineWidth', 1);
grid on
title('Joint Angles')
ylabel('Angle (deg)')
legend({'Pivot','Bicep','Forearm','Wrist'},'Location','Best');

if (max(simlog_joint_pos.Values.Time)>3.4)
    simlog_handles(2) = subplot(2, 1, 2);
    plot(simlog_joint_pos.Values.Time, simlog_joint_pos.Values.Data(:,6:7), 'LineWidth', 1);
    title('Finger Position')
    ylabel('Position (mm)')
    grid on
    xlabel('Time (s)')
    legend({'Finger A','Finger B'},'Location','Best');
end

% Plot waypoints if this is a spline test
if (max(simlog_joint_pos.Values.Time)<3.4)
    temp_Qt_inds = [...
        find(simlog_joint_pos.Values.Time == t(2))...
        find(simlog_joint_pos.Values.Time == t(3))...
        find(simlog_joint_pos.Values.Time == t(4))];
    
    hold on
    plot(simlog_joint_pos.Values.Time(temp_Qt_inds), simlog_joint_pos.Values.Data(temp_Qt_inds,1)*180/pi,'d','MarkerEdgeColor','k','MarkerFaceColor','k');
    plot(simlog_joint_pos.Values.Time(temp_Qt_inds), simlog_joint_pos.Values.Data(temp_Qt_inds,2)*180/pi,'d','MarkerEdgeColor','k','MarkerFaceColor','k');
    plot(simlog_joint_pos.Values.Time(temp_Qt_inds), simlog_joint_pos.Values.Data(temp_Qt_inds,3)*180/pi,'d','MarkerEdgeColor','k','MarkerFaceColor','k');
    plot(simlog_joint_pos.Values.Time(temp_Qt_inds), simlog_joint_pos.Values.Data(temp_Qt_inds,4)*180/pi,'d','MarkerEdgeColor','k','MarkerFaceColor','k');
    legend({'Pivot','Bicep','Forearm','Wrist','Waypoints'},'Location','Best');
    xlabel('Time (s)')
end

% Remove temporary variables
clear simlog_motor_currents temp_t
clear temp_colororder

