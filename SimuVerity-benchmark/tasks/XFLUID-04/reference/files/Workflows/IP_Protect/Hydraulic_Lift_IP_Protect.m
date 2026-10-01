% Protect model containing Simscape components
% and test with varying parameters.

% Copyright 2013-2025 The MathWorks(TM), Inc.

cd(fileparts(which(mfilename)))

% Open model, create copy
orig_mdl = 'ssc_hydraulic_lift';
mdl = [orig_mdl '_protected'];
refmdl = 'Hydraulic_Lift';
refsys = [mdl '/' refmdl];
open_system(orig_mdl);

ssc_hydraulic_lift_setdefault(orig_mdl)
ssc_hydraulic_lift_tictoc(orig_mdl,'off')
%set_param([orig_mdl '/SLRT Scope'],'Commented','on');
set_param(orig_mdl,'SimscapeLogType','none');
set_param([orig_mdl '/Servo and Controller/Custom/Rotational Damper'],'D_conf','runtime');

save_system(orig_mdl,mdl);


%% Create subsystem to be protected
bh(1) = get_param([mdl '/Load'],'Handle');
bh(2) = get_param([mdl '/MTRef'],'Handle');
bh(3) = get_param([mdl '/Actuator'],'Handle');
bh(4) = get_param([mdl '/Valve'],'Handle');
bh(5) = get_param([mdl '/Pump and Tank'],'Handle');
bh(6) = get_param([mdl '/Servo and Controller'],'Handle');
bh(7) = get_param([mdl '/Controller'],'Handle');
bh(8) = get_param([mdl '/Sensing Cmd'],'Handle');
bh(9) = get_param([mdl '/Sensing'],'Handle');
Simulink.BlockDiagram.createSubSystem(bh);
set_param([mdl '/Subsystem'],...
    'Name',refmdl,...
    'Position',[-40   405    65   485],...
    'Orientation','right');

%% Create Reference Model
set_param(refsys,'TreatAsAtomicUnit','on');
warning('off','Simulink:protectedModel:ProtectedModelCallbackLostWarning')
Simulink.SubSystem.convertToModelReference(...
   refsys,refmdl, ...
   'AutoFix',true,...
   'ReplaceSubsystem',true);

%% Configure Reference Model
open_system(refmdl);
set_param(refmdl,'SimscapeLogType','none');
set_param(refmdl,'ModelReferenceNumInstancesAllowed','single');
set_param(refmdl,'SimMechanicsUnconnectedFramePorts','none');
save_system(refmdl);

%% Create and reference protected model
[harnessHandle, neededVars] = ...
    Simulink.ModelReference.protect(refmdl,...
    'Harness', false,...
    'Webview',true, ...
    'TunableParameters', {'motor_damping'});
set_param(refsys,'ModelName',[refmdl '.slxp']);
bdclose(refmdl);

%% Run simulation with modified parameter value
motor_damping.Value = 0.01*20;
sim(mdl);
t_run1 = LoadPosition_DATA.time;
y_run1 = LoadPosition_DATA.signals.values(:,2);
y_ref = LoadPosition_DATA.signals.values(:,1);

motor_damping.Value = 0.2*5;
sim(mdl);
t_run2 = LoadPosition_DATA.time;
y_run2 = LoadPosition_DATA.signals.values(:,2);

figure(1); clf;
temp_colorOrder = get(gca,'DefaultAxesColorOrder');
plot(t_run1,y_ref,'Color','k','LineWidth',1,'LineStyle','--');
hold on
plot(t_run1,y_run1,'LineWidth',2,'Color',temp_colorOrder(1,:));
plot(t_run2,y_run2,'LineWidth',2,'Color',temp_colorOrder(2,:));
hold off
title('Servomotor Damping Test');
grid on
xlabel('Time (s');ylabel('Angle (deg)');
legend({'Command','Normal','Aged'},'Location','Best');


%% Close model and clean up directory

bdclose(mdl); 
delete([mdl '.slx']);
bdclose(refmdl);
delete([refmdl '.slx']);
% Not necessary inside a project
delete([refmdl '.slxp']);
%delete('*.mex*')
%!rmdir slprj /S/Q

