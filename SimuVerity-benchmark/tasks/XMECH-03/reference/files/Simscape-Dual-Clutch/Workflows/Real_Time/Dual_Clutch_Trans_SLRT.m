%% Open model resave for real-time test
orig_mdl = 'Dual_Clutch_Trans';
open_system(orig_mdl);
mdl = [orig_mdl '_rttest_temp'];
save_system(orig_mdl,mdl);

Drive_Cycle_Num = 6;
DCT_Vehicle_Mass = 1600;

% Code for runtime parameter test with Full variant
set_param([bdroot '/Vehicle Dynamics'],'LabelModeActiveChoice','Full')
set_param(mdl,'StopTime','15');
set_param(mdl,'SimscapeLogType','None');

% Code for runtime parameter test with Simple variant
%set_param([mdl '/Vehicle Dynamics/Simple'],'LinkStatus','inactive')
%set_param([mdl '/Vehicle Dynamics/Simple'],'mass','DCT_Vehicle_Mass');

%% Get reference results
Dual_Clutch_Trans_setsolver(mdl,'desktop')
set_param(mdl,'SimulationMode','normal')
sim(mdl)

log_meas = logsout_Dual_Clutch_Trans.get('Vehicle_Speed');
t_ref = log_meas.Values.Time; y_ref = log_meas.Values.Data;

%% Create plot for comparing results
figure(1); clf;
temp_colororder = get(gca,'DefaultAxesColorOrder');
set(gcf,'Position',[552    50   472   301]);
plot(t_ref,y_ref,'k','LineWidth',3)
title('Comparing Simulation Results','FontSize',14,'FontWeight','Bold');
xlabel('Time (s)','FontSize',12);ylabel('Vehicle Speed');
legend({'Reference'},'Location','SouthEast')

%% Test with fixed-step, fixed-cost solver
Dual_Clutch_Trans_setsolver(mdl,'realtime')
sim(mdl)
log_meas = logsout_Dual_Clutch_Trans.get('Vehicle_Speed');
t_fs = log_meas.Values.Time; y_fs = log_meas.Values.Data;

%% Add fixed-step results to plot
figure(1)
hold on
h2=stairs(t_fs, y_fs,'Color',temp_colororder(2,:),'LineWidth',2.5);
hold off
legend({'Reference','Fixed-Step'},'Location','NorthWest')

%% Enable real-time parameter
% Code for run-time parameter test in Full variant
tune_bpth = [mdl '/Vehicle Dynamics/Full/Vehicle Body'];

% Code for run-time parameter test in Simple variant
%tune_bpth = [mdl '/Vehicle Dynamics/Simple/Inertia'];
%set_param(tune_bpth,'inertia_conf','runtime');
%set_param(tune_bpth,'mass_conf','runtime');

% Highlight block
open_system(get_param(tune_bpth,'Parent'),'force')
set_param(tune_bpth,'Selected','on');

%% Build and download to real-time target
% Choose target
cs = getActiveConfigSet(mdl);
cs.switchTarget('slrealtime.tlc',[]);

slbuild(mdl);

%% Download to real-time target
tg = slrealtime;
tg.connect;

%% Run application
tg.load(mdl)
tg.start('ReloadOnStop',true,'ExportToBaseWorkspace',true)

open_system(mdl);
disp('Waiting for SLRT to finish...');
pause(1);
while(strcmp(tg.status,'running'))
    pause(2);
    disp(tg.status);
end
pause(2);

%% Extract results from logged data in Simulink Data Inspector
y_slrt1 = logsout_Dual_Clutch_Trans.getElement('Vehicle_Speed');

%% Add results from real-time simulation
figure(1)
hold on
h3=stairs(y_slrt1.Values.Time,y_slrt1.Values.Data,'c:','LineWidth',2.5);
hold off
legend({'Reference','Fixed-Step','Real-Time'},'Location','NorthWest');

%% Change a Simscape block parameter
% Code for runtime parameter test in Full variant
tg_DCT_Param = getparam(tg,'','DCT_Param');
disp(['Vehicle Mass (current) = ' num2str(tg_DCT_Param.Vehicle.Mass)]);
tg_DCT_Param.Vehicle.Mass = 1800;
setparam(tg,'','DCT_Param',tg_DCT_Param);
tg_DCT_Param = getparam(tg,'','DCT_Param');
disp(['Vehicle Mass (new)     = ' num2str(tg_DCT_Param.Vehicle.Mass)]);

% Code for runtime parameter test in Simple variant
%disp(['Vehicle Mass (current) = ' num2str(getparam(tg,'','DCT_Vehicle_Mass'))]);
%setparam(tg,'','DCT_Vehicle_Mass',1800)
%disp(['Vehicle Mass (new)     = ' num2str(getparam(tg,'','DCT_Vehicle_Mass'))]);

%% Run simulation on real-time hardware
tg.start('ReloadOnStop',true,'ExportToBaseWorkspace',true)

disp('Waiting for Simulink Real-Time to finish...');
pause(1);
while(strcmp(tg.status,'running'))
    pause(2);
    disp(tg.status);
end
pause(2);

%% Extract results from logged data in Simulink Data Inspector
y_slrt2 = logsout_Dual_Clutch_Trans.getElement('Vehicle_Speed');

%% Add results from modified vehicle model
figure(1)
hold on
h4=stairs(y_slrt2.Values.Time,y_slrt2.Values.Data,'Color',temp_colororder(4,:),'LineWidth',2);
hold off
legend({'Reference','Fixed-Step','Real-Time','Modified'},'Location','NorthWest');

% Copyright 2011-2025 The MathWorks(TM), Inc.
%% Close model and clean up directory
%cleanup_rt_dir
