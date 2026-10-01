% Code to plot simulation results from youBot_Arm
%% Plot Description:
%
% The plot below shows the current drawn by all motors in the youBot
% robotic arm.
%
% Copyright 2016-2025 The MathWorks, Inc.

% Generate simulation results if they don't exist
if ~exist('simlog_youBot_Arm', 'var')
    sim('youBot_Arm')
end

% Reuse figure if it exists, else create new figure
if ~exist('h1_youBot_Arm', 'var') || ...
        ~isgraphics(h1_youBot_Arm, 'figure')
    h1_youBot_Arm = figure('Name', 'youBot_Arm');
end
figure(h1_youBot_Arm)
clf(h1_youBot_Arm)

temp_colororder = get(gca,'defaultAxesColorOrder');

% Get simulation results
simlog_motor_currents = logsout_youBot_Arm.get('motor_currents');
temp_t = simlog_motor_currents.Values.Time;

% Plot results
plot(temp_t, simlog_motor_currents.Values.Data, 'LineWidth', 1)
grid on
title('Motor Currents')
ylabel('Current (A)')
legend({'Pivot','Bicep','Forearm','Wrist','Gripper','Finger A','Finger B'},'Location','Best');

xlabel('Time (s)')


% Remove temporary variables
clear simlog_motor_currents temp_t
clear temp_colororder

