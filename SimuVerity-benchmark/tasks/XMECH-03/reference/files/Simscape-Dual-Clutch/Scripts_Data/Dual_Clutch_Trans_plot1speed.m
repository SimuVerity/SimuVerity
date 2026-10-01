% Code to plot simulation results from Dual_Clutch_Trans
%% Plot Description:
%
% The plots below show the engine and vehicle speed as it accelerates
% through the first three gears in the dual-clutch transmission.  The
% half-gear states indicate gear shifts are taking place by engaging and
% disengaging the dual clutches.

% Copyright 2016-2025 The MathWorks, Inc.

% Generate simulation results if they don't exist
if ~exist('simlog_Dual_Clutch_Trans', 'var')
    sim('Dual_Clutch_Trans')
end

% Reuse figure if it exists, else create new figure
if ~exist('h1_Dual_Clutch_Trans', 'var') || ...
        ~isgraphics(h1_Dual_Clutch_Trans, 'figure')
    h1_Dual_Clutch_Trans = figure('Name', 'Dual_Clutch_Trans');
end
figure(h1_Dual_Clutch_Trans)
clf(h1_Dual_Clutch_Trans)

% Get simulation results
simlog_vVeh = logsout_Dual_Clutch_Trans.get('Vehicle_Speed');
simlog_wEngine = logsout_Dual_Clutch_Trans.get('Engine_Speed');
simlog_pClutches = logsout_Dual_Clutch_Trans.get('Clutch_Pressures');

simlog_Gear = logsout_Dual_Clutch_Trans.get('Gear_State');

% Plot results
simlog_handles(1) = subplot(2, 1, 1);
yyaxis left
plot(simlog_vVeh.Values.Time, simlog_vVeh.Values.Data, 'LineWidth', 1)
ylabel('Speed (kph)')
yyaxis right
plot(simlog_wEngine.Values.Time, simlog_wEngine.Values.Data, 'LineWidth', 1)
ylabel('Speed (RPM)')
grid on
title('Vehicle and Engine Speeds')
legend({'Vehicle','Engine'},'Location','Best');
textstr1 = sprintf('Number of Steps:\nElapsed Time:');
textstr2 = sprintf('%d\n%3.2f',length(simlog_vVeh.Values.Time),Elapsed_Sim_Time);
text(0.2,0.15,textstr1,'Color',[1 1 1]*0.6,'Units','Normalized')
text(0.55,0.15,textstr2,'Color',[1 1 1]*0.6,'Units','Normalized','HorizontalAlignment','Right')

textstr1 = sprintf('Transmission:\nVehicle:');
textstr2 = sprintf('%s\n%s',...
    get_param('Dual_Clutch_Trans/Dual Clutch Transmission','LabelModeActiveChoice'),...
    get_param('Dual_Clutch_Trans/Vehicle Dynamics','LabelModeActiveChoice'));
text(0.6,0.15,textstr1,'Color',[1 1 1]*0.6,'Units','Normalized')
text(0.8,0.15,textstr2,'Color',[1 1 1]*0.6,'Units','Normalized')

simlog_handles(2) = subplot(2, 1, 2);
yyaxis left
plot(simlog_pClutches.Values.Time, simlog_pClutches.Values.Data, 'LineWidth', 1)
hold off
ylabel('Pressure (Pa)')
yyaxis right
plot(simlog_Gear.Values.Time, simlog_Gear.Values.Data, 'LineWidth', 1)
grid on
ylabel('Gear')
title('Clutch Pressures and Selected Gear')
ylabel('Gear')
xlabel('Time (s)')
legend({'Odd Clutch','Even Clutch','Gear'},'Location','Best');

linkaxes(simlog_handles, 'x')

% Remove temporary variables
%clear simlog_t simlog_handles
%clear simlog_vVeh simlog_wEngine simlog_pClOdd simlog_pClEven temp_Gear