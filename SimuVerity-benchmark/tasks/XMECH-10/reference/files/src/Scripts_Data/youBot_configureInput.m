function youBot_configureInput(modelname,variant)
% Copyright 2016-2025 The MathWorks, Inc.

in_pth = find_system(modelname,'MatchFilter',@Simulink.match.allVariants,...
    'LookUnderMasks','all','FollowLinks','on',...
    'Variant','on','Name','Input');

set_param(char(in_pth),'OverrideUsingVariant',variant);
end
