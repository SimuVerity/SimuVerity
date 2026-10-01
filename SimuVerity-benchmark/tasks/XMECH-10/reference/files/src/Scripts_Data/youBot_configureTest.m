function youBot_configureTest(modelname,testOption)
% Copyright 2016-2025 The MathWorks, Inc.

sigbRobt_hs = find_system(modelname,'MatchFilter',@Simulink.match.allVariants,...
    'LookUnderMasks','all',...
    'FollowLinks','on',...
    'Name','Robot Commands');
sigbRobt_h = sigbRobt_hs{2};

sigbBelt_hs = find_system(modelname,'MatchFilter',@Simulink.match.allVariants,...
    'LookUnderMasks','all',...
    'FollowLinks','on',...
    'Name','Belt Commands');
sigbBelt_h = sigbBelt_hs{1};


[time_sb, data_sb, ~, groupnamesRC] = signalbuilder(sigbRobt_h);
[~, ~, ~, groupnamesBC] = signalbuilder(sigbBelt_h);

switch testOption
    case 'Default'
        youBot_configureActuation(modelname,'Motion');
        youBot_configureLoad(modelname,'Damper');
        youBot_configureInput(modelname,'Control');
        set_param(modelname,'StopTime','20');
    case 'BoxFlip'
        youBot_configureActuation(modelname,'Motion');
        youBot_configureLoad(modelname,'Payload');
        youBot_configureInput(modelname,'Signals');
        set_param(modelname,'StopTime','3.3');
        signalbuilder(sigbRobt_h, 'activegroup',...
            find(strcmp('Opt Flip Orig',groupnamesRC)));
        signalbuilder(sigbBelt_h, 'activegroup',...
            find(strcmp('Locked',groupnamesBC)));
    case {'Optim_Manual','Optim_NoFriction','Optim_Friction',...
            'Home2In','Out2Home'}
        youBot_configureActuation(modelname,'Motion');
        youBot_configureLoad(modelname,'Payload');
        youBot_configureInput(modelname,'Splines');
        set_param(modelname,'StopTime','3.3');
        switch testOption
            case 'Optim_Manual'
                evalin('base','t  = YBT_Par.Waypoints.In2Out.Manual.t;');
                evalin('base','Qt = YBT_Par.Waypoints.In2Out.Manual.q;');
            case 'Optim_NoFriction'
                evalin('base','t  = YBT_Par.Waypoints.In2Out.OptNoFriction.t;');
                evalin('base','Qt = YBT_Par.Waypoints.In2Out.OptNoFriction.q;');
            case 'Optim_Friction'
                evalin('base','t  = YBT_Par.Waypoints.In2Out.OptFriction.t;');
                evalin('base','Qt = YBT_Par.Waypoints.In2Out.OptFriction.q;');
            case 'Home2In'
                evalin('base','t  = YBT_Par.Waypoints.Home2In.Manual.t;');
                evalin('base','Qt = YBT_Par.Waypoints.Home2In.Manual.q;');
            case 'Out2Home'
                evalin('base','t  = YBT_Par.Waypoints.Out2Home.Manual.t;');
                evalin('base','Qt = YBT_Par.Waypoints.Out2Home.Manual.q;');
            otherwise
                error('Test option not defined');
        end
    case {'Test Pivot','Test Bicep','Test Forearm','Test Wrist',...
            'Test Max Torque','Test All 35'}
        youBot_configureActuation(modelname,'Motion');
        youBot_configureLoad(modelname,'Payload');
        youBot_configureInput(modelname,'Signals');
        signalbuilder(sigbRobt_h, 'activegroup',...
            find(strcmp(testOption,groupnamesRC)));
        signalbuilder(sigbBelt_h, 'activegroup',...
            find(strcmp('Locked',groupnamesBC)));
        set_param(modelname,'StopTime',...
            num2str(max(time_sb{1,strcmp(testOption,groupnamesRC)})));
    otherwise
        error('Test option not defined');
end

% Commands update text label on mask without requiring Update Diagram
set_param([bdroot '/Input'],'Name','Input');
set_param([bdroot '/Input/Signals'],'Name','Signals');


