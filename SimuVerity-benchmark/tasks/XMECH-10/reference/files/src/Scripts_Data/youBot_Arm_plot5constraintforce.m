% Code to plot simulation results from youBot_Arm
%% Plot Description:
%
% The plot below shows the constraint forces for each joint in the youBot
% robotic arm.
%
% Copyright 2016-2025 The MathWorks, Inc.

% Generate simulation results if they don't exist
if ~exist('simlog_youBot_Arm', 'var')
    sim('youBot_Arm')
end

% Reuse figure if it exists, else create new figure
if ~exist('h5_youBot_Arm', 'var') || ...
        ~isgraphics(h5_youBot_Arm, 'figure')
    h5_youBot_Arm = figure('Name', 'youBot_Arm');
end
figure(h5_youBot_Arm)
clf(h5_youBot_Arm)

temp_colororder = get(gca,'defaultAxesColorOrder');

% Get simulation results
simlog_joint_fc = logsout_youBot_Arm.get('joint_fc');
temp_t = simlog_joint_fc.Values.Time;

temp_radInds = [1 2;4 5;7 8; 10 11;13 14; 16 17; 19 20];
temp_axInds = [1:7]*3;

% Plot results
simlog_handles(1) = subplot(2, 1, 1);
for temp_jNum = 1:7
    temp_fcAxial = sqrt(...
        simlog_joint_fc.Values.Data(:,temp_radInds(temp_jNum,1)).^2 + ...
        simlog_joint_fc.Values.Data(:,temp_radInds(temp_jNum,2)).^2); 
    plot(temp_t, temp_fcAxial, 'LineWidth', 1);
    hold on;
    temp_maxAxFc(temp_jNum) = max(temp_fcAxial);
end
hold off
grid on
title('Constraint Forces: Radial')
ylabel('Force (N)')
%temp_maxTorF = max(abs(simlog_joint_fc.Values.Data));
legend({...
    ['Pivot:      Max=' sprintf('%2.2f',temp_maxAxFc(1)) ' N'],...
    ['Bicep:     Max=' sprintf('%2.2f',temp_maxAxFc(2)) ' N'],...
    ['Forearm: Max=' sprintf('%2.2f',temp_maxAxFc(3)) ' N'],...
    ['Wrist:      Max=' sprintf('%2.2f',temp_maxAxFc(4)) ' N'],...
    ['Gripper:   Max=' sprintf('%2.2f',temp_maxAxFc(5)) ' N'],...
    ['Finger A:  Max=' sprintf('%2.2f',temp_maxAxFc(6)) ' N'],...
    ['Finger B:  Max=' sprintf('%2.2f',temp_maxAxFc(7)) ' N']},...
    'Location','Best');

simlog_handles(2) = subplot(2, 1, 2);
plot(temp_t, simlog_joint_fc.Values.Data(:,temp_axInds), 'LineWidth', 1);
hold off
grid on
title('Constraint Forces: Axial')
ylabel('Force (N)')
temp_maxAxF = max(abs(simlog_joint_fc.Values.Data(:,temp_axInds)));
legend({...
    ['Pivot:      Max=' sprintf('%2.2f',temp_maxAxF(1)) ' N'],...
    ['Bicep:     Max=' sprintf('%2.2f',temp_maxAxF(2)) ' N'],...
    ['Forearm: Max=' sprintf('%2.2f',temp_maxAxF(3)) ' N'],...
    ['Wrist:      Max=' sprintf('%2.2f',temp_maxAxF(4)) ' N'],...
    ['Gripper:   Max=' sprintf('%2.2f',temp_maxAxF(5)) ' N'],...
    ['Finger A:  Max=' sprintf('%2.2f',temp_maxAxF(6)) ' N'],...
    ['Finger B:  Max=' sprintf('%2.2f',temp_maxAxF(7)) ' N']},...
    'Location','Best');


xlabel('Time (s)')


% Remove temporary variables
clear simlog_motor_currents temp_t
clear temp_colororder

