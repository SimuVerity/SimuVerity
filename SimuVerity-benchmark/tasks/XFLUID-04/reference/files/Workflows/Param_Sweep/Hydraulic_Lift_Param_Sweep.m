%% Use Parallel Computing and Fast Restart to sweep parameter value
% Copyright 2013-2025 The MathWorks(TM), Inc.

% Move to folder where script is saved
cd(fileparts(which(mfilename)));

% Open model and save under another name for test
orig_mdl = 'ssc_hydraulic_lift';
open_system(orig_mdl);
mdl = [orig_mdl '_pct_temp'];
save_system(orig_mdl,mdl);

%% Configure model for tests
ssc_hydraulic_lift_setdefault(mdl)
ssc_hydraulic_lift_tictoc(mdl,'off')
set_param([mdl '/SLRT Scope'],'Commented','on');
set_param(mdl,'SimscapeLogType','none');
set_param([mdl '/Servo and Controller/Custom/Rotational Damper'],'D_conf','runtime');
save_system(mdl);

%% Generate parameter sets
motordamp_array = [0.01:0.01:0.2]; 

for i=1:length(motordamp_array)
    simInput(i) = Simulink.SimulationInput(mdl);
    simInput(i) = simInput(i).setVariable('motor_damping',motordamp_array(i));
end

%% Run one simulation to see time used
timerVal = tic;
sim(mdl)
Elapsed_Sim_Time_single = toc(timerVal);
disp(['Elapsed Simulation Time Single Run: ' num2str(Elapsed_Sim_Time_single)]);

%% Adjust settings and save
set_param(mdl,'SimMechanicsOpenEditorOnUpdate','off');
save_system(mdl)

%% Run parameter sweep in parallel
timerVal = tic;
simOut = parsim(simInput,'ShowSimulationManager','on',...
    'ShowProgress','on','UseFastRestart','on',...
    'TransferBaseWorkspaceVariables','on');
Elapsed_Time_Time_parallel  = toc(timerVal);

%% Calculate elapsed time less setup of parallel
Elapsed_Time_Sweep = ...
    (datenum(simOut(end).SimulationMetadata.TimingInfo.WallClockTimestampStop) - ...
    datenum(simOut(1).SimulationMetadata.TimingInfo.WallClockTimestampStart)) * 86400;
disp(['Elapsed Sweep Time Total:       ' sprintf('%5.2f',Elapsed_Time_Sweep)]);
disp(['Elapsed Sweep Time/(Num Tests): ' sprintf('%5.2f',Elapsed_Time_Sweep/length(simOut))]);

%% Plot results
plot_sim_res(simOut,'Parallel Test',Elapsed_Time_Time_parallel)

%% Close parallel pool
delete(gcp);

%% Cleanup directory
bdclose(mdl);
delete([mdl '.slx']);

%%  Plot function
function plot_sim_res(simOut,annotation_str,elapsed_time)

% Plot Results
fig_handle_name =   'h4_ssc_hydraulic_lift_pct';

handle_var = evalin('base',['who(''' fig_handle_name ''')']);
if(isempty(handle_var))
    evalin('base',[fig_handle_name ' = figure(''Name'', ''' fig_handle_name ''');']);
elseif ~isgraphics(evalin('base',handle_var{:}))
    evalin('base',[fig_handle_name ' = figure(''Name'', ''' fig_handle_name ''');']);
end
figure(evalin('base',fig_handle_name))
clf(evalin('base',fig_handle_name))

for i=1:length(simOut)
    data = simOut(i).LoadPosition_DATA;
    plot(data.time(:,1),data.signals.values(:,2))
    hold all
end
plot(data.time(:,1),data.signals.values(:,1),'k--','LineWidth',1)
title('Parameter Sweep Results');
xlabel('Time (s)');
ylabel('Load Position');

text(0.1,0.15,sprintf('%s\n%s',annotation_str,['Elapsed Time: ' num2str(elapsed_time)]),'Color',[1 1 1]*0.6,'Units','Normalized');
end