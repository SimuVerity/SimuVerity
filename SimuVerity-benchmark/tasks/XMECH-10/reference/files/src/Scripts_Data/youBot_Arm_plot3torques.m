% Code to plot simulation results from youBot_Arm
%% Plot Description:
%
% The plot below shows the torque or force for each motor in the youBot
% robotic arm.
%
% Copyright 2016-2025 The MathWorks, Inc.

% Generate simulation results if they don't exist
if ~exist('simlog_youBot_Arm', 'var')
    sim('youBot_Arm')
end

% Reuse figure if it exists, else create new figure
if ~exist('h3_youBot_Arm', 'var') || ...
        ~isgraphics(h3_youBot_Arm, 'figure')
    h3_youBot_Arm = figure('Name', 'youBot_Arm');
end
figure(h3_youBot_Arm)
clf(h3_youBot_Arm)

temp_colororder = get(gca,'defaultAxesColorOrder');

% Get simulation results
simlog_motor_torques = logsout_youBot_Arm.get('motor_torques');
temp_t = simlog_motor_torques.Values.Time;


% Plot results
plot(temp_t, simlog_motor_torques.Values.Data, 'LineWidth', 1)
grid on
title('Motor Torques and Forces')
ylabel('Torque (Nm), Force (N)')
temp_maxTorF = max(abs(simlog_motor_torques.Values.Data));
legend({...
    ['Pivot:      Max=' sprintf('%2.2f',temp_maxTorF(1)) ' Nm'],...
    ['Bicep:     Max=' sprintf('%2.2f',temp_maxTorF(2)) ' Nm'],...
    ['Forearm: Max=' sprintf('%2.2f',temp_maxTorF(3)) ' Nm'],...
    ['Wrist:      Max=' sprintf('%2.2f',temp_maxTorF(4)) ' Nm'],...
    ['Gripper:   Max=' sprintf('%2.2f',temp_maxTorF(5)) ' Nm'],...
    ['Finger A:  Max=' sprintf('%2.2f',temp_maxTorF(6)) ' N'],...
    ['Finger B:  Max=' sprintf('%2.2f',temp_maxTorF(7)) ' N']},...
    'Location','Best');

xlabel('Time (s)')


% Remove temporary variables
clear simlog_motor_currents temp_t
clear temp_colororder

