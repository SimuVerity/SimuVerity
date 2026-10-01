function youBot_configureLoad(modelname,option)
% Copyright 2016-2025 The MathWorks, Inc.

gf_pth = find_system(modelname,'MatchFilter',@Simulink.match.allVariants,...
    'LookUnderMasks','all','FollowLinks','on',...
    'Variant','on','Name','Gripper Force');

ld_pth = find_system(modelname,'MatchFilter',@Simulink.match.allVariants,...
    'LookUnderMasks','all','FollowLinks','on',...
    'Variant','on','Name','Load');

switch option
    case 'Payload'
        set_param(char(gf_pth),'OverrideUsingVariant','Payload');
        set_param(char(ld_pth),'OverrideUsingVariant','None');
    case 'Damper'
        set_param(char(gf_pth),'OverrideUsingVariant','Damper');
        set_param(char(ld_pth),'OverrideUsingVariant','Box');
    case 'Penalty'
        set_param(char(gf_pth),'OverrideUsingVariant','Penalty');
        set_param(char(ld_pth),'OverrideUsingVariant','Box');
    otherwise
        error('Configuration option not recognized')
end
end
