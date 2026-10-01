% Copyright 2013-2025 MathWorks, Inc.
load_system(mdl);

% RESET SYSTEM VARIANTS
set_param([mdl '/Dual Clutch Transmission'],'OverrideUsingVariant','Detailed');
set_param([mdl '/Vehicle Dynamics'],'OverrideUsingVariant','Simple');
set_param([mdl '/Engine'],'OverrideUsingVariant','Generic');

% TURN ON LOGGING
set_param([mdl '/Scopes/Engine'],'SaveToWorkspace','on');
set_param([mdl '/Scopes/Vehicle speed'],'SaveToWorkspace','on');
set_param([mdl '/Scopes/Gear'],'SaveToWorkspace','on');
set_param([mdl '/Transmission Controller/Driver/Driver'],'SaveToWorkspace','on');
set_param([mdl '/Fuel Economy/Fuel Flow'],'SaveToWorkspace','on');
set_param(mdl,'SimscapeLogType','All')

% SIMULATION SETTINGS
Dual_Clutch_Trans_setsolver(mdl,'desktop');
Dual_Clutch_Trans_tictoc(mdl,'off');
set_param(mdl,'SimulationMode','normal')

% DRIVE CYCLE
Drive_Cycle_Num = 7;
set_param(mdl,'StopTime','174');

% SAVE FILE
warning off Simulink:Commands:SetParamLinkChangeWarn
warning off Simulink:Engine:SaveWithParameterizedLinks_Warning
save_system(mdl);
close_system(mdl);
