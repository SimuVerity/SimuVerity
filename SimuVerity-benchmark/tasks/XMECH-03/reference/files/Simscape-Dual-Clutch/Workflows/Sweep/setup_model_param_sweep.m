% Copyright 2013-2025 MathWorks, Inc.
load_system(mdl);

% SELECT SYSTEM VARIANTS
set_param([mdl '/Dual Clutch Transmission'],'LabelModeActiveChoice','Abstracted');
set_param([mdl '/Vehicle Dynamics'],'LabelModeActiveChoice','Simple');
set_param([mdl '/Engine'],'LabelModeActiveChoice','Generic');

% TURN OFF LOGGING
set_param([mdl '/Scopes/Engine'],'SaveToWorkspace','off');
set_param([mdl '/Scopes/Vehicle speed'],'SaveToWorkspace','off');
set_param([mdl '/Scopes/Gear'],'SaveToWorkspace','off');
set_param([mdl '/Transmission Controller/Driver/Driver'],'SaveToWorkspace','off');
set_param([mdl '/Fuel Economy/Fuel Flow'],'SaveToWorkspace','off');
set_param(mdl,'SimscapeLogType','None');

% SIMULATION SETTINGS
%set_param(mdl,'SimulationMode','rapid-accelerator');
%set_param(mdl,'SimulationMode','accelerator');
%Dual_Clutch_Trans_setsolver(mdl,'realtime')
Dual_Clutch_Trans_tictoc(mdl,'off');

% DRIVE CYCLE
Drive_Cycle_Num = 7;
set_param(mdl,'StopTime','174');

% SAVE FILE
warning off Simulink:Commands:SetParamLinkChangeWarn
warning off Simulink:Engine:SaveWithParameterizedLinks_Warning
save_system(mdl);
close_system(mdl);
