%% Script to run ssc_hydraulic_lift in parallel

% Resave model in PCT directory
cd(fileparts(which('ssc_hydraulic_lift.slx')));
cd(['Workflows' filesep 'Param_Sweep']);
orig_mdl = 'ssc_hydraulic_lift';
open_system(orig_mdl);
mdl = [orig_mdl '_pct_temp'];
ssc_hydraulic_lift_setdefault(orig_mdl)
ssc_hydraulic_lift_tictoc(orig_mdl,'off')
set_param([orig_mdl '/SLRT Scope'],'Commented','on');
set_param(orig_mdl,'SimscapeLogType','none');
set_param([orig_mdl '/Servo and Controller/Custom/Rotational Damper'],'D_conf','runtime');
save_system(orig_mdl,mdl);

%clear motor_damping;
%motor_damping = 0.01;

%% BUILD TARGET
rtp = Simulink.BlockDiagram.buildRapidAcceleratorTarget(mdl);

%% GENERATE PARAMETER SETS
motordamp_array = [0.01:0.01:0.2]; 
SimSettings = Generate_Sim_Settings(motordamp_array,'motor_damping',rtp);

numSims = length(SimSettings);
out = cell(1, numSims);

%% START PARALLEL POOL
parpool(2);
Initialize_MLPool

%% SIMULATE
tic;
parfor i = 1:numSims
    out{i} = sim(mdl, SimSettings{i});
end
Total_Testing_Time = toc;
disp(['Total Testing Time = ' num2str(Total_Testing_Time)]);

%% PLOT RESULTS
figure(1)
set(gcf,'Position',[15    52   545   355]);

for i=1:numSims
    data = out{i}.find('LoadPosition_DATA');
    plot(data.time(:,1),data.signals.values(:,2))
    hold all
end
plot(data.time(:,1),data.signals.values(:,1),'k--','LineWidth',1)
title('Parameter Sweep Results');
xlabel('Time (s)');
ylabel('Load Position');

%% CLOSE PARALLEL POOL
delete(gcp);

%% CLEANUP DIR
bdclose(mdl);
delete([mdl '.slx']);

% Copyright 2013-2025 The MathWorks(TM), Inc.

