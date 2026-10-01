% Code to plot simulation results from ball_on_conveyor
%% Plot Description:
%
% The plot below shows the 3D trajectory of the box moved by the gripper.
%
% Copyright 2017-2026 The MathWorks, Inc.

% Generate simulation results if they don't exist
if ~exist('simlog_ball_on_conveyor', 'var')
    sim('ball_on_conveyor')
end

% Reuse figure if it exists, else create new figure
if ~exist('h1_ball_on_conveyor', 'var') || ...
        ~isgraphics(h1_ball_on_conveyor, 'figure')
    h1_ball_on_conveyor = figure('Name', 'ball_on_conveyor');
end
figure(h1_ball_on_conveyor)
clf(h1_ball_on_conveyor)

temp_colororder = get(gca,'defaultAxesColorOrder');

% Get simulation results
logsout_Belt = logsout_ball_on_conveyor.get('BeltForces');
logsout_Ball = logsout_ball_on_conveyor.get('Ball');
logsout_vtBall = logsout_ball_on_conveyor.get('vtBall');

logsout_FfriX = squeeze(logsout_Belt.Values.Ff.x.Data);
logsout_FfriY = squeeze(logsout_Belt.Values.Ff.y.Data);
logsout_FfriM = squeeze(logsout_Belt.Values.Ff.mag.Data);
logsout_vtx   = squeeze(logsout_Belt.Values.vt.x.Data);
logsout_time  = squeeze(logsout_Belt.Values.vt.x.Time);

logsout_wzBall = logsout_Ball.Values.wz.Data;
logsout_vxBall = logsout_Ball.Values.vx.Data;

logsout_vtBallD = logsout_vtBall.Values.Data;

% Plot results
simlog_handles(1) = subplot(3,1,1);
plot(logsout_time,logsout_vtx,'LineWidth',1,'DisplayName','Belt');
hold on
plot(logsout_time,logsout_vtBallD,'--','LineWidth',1,'DisplayName','Ball');
hold off
title('Tangential Velocity')
legend('Location','Best');
grid on
ylabel('Speed (m/s)')

simlog_handles(2) = subplot(3,1,2);
plot(logsout_time,logsout_vtBallD-logsout_vtx,'LineWidth',1);
title('Slip Velocity')
grid on
ylabel('Speed (m/s)')

simlog_handles(3) = subplot(3,1,3);
plot(logsout_time,logsout_FfriX,'LineWidth',1,'DisplayName','Fx');
hold on
plot(logsout_time,logsout_FfriY,'--','LineWidth',1,'DisplayName','Fy');
plot(logsout_time,logsout_FfriM,'-.','LineWidth',1,'DisplayName','mag');
hold off
grid on
title('Friction Force')
text(0.95,0.15,[sprintf('%3.2f', Elapsed_Sim_Time) ' sec, ' num2str(length(tout)) ' Steps'],...
    'Units','normalized','Color',[0.6 0.6 0.6],...
    'HorizontalAlignment','right');
xlabel('Time (s)')
ylabel('Force (N)')
legend('Location','Best');


% Remove temporary variables
clear simlog_t simlog_boxPx simlog_boxPy simlog_boxPz
clear temp_colororder

