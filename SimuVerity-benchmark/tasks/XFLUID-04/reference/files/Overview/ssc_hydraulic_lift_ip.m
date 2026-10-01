%% IP Protection for Hydraulic Lift Model
%
% This example models a hydraulic lift.  We use code generation technology
% to create a protected model of the hydraulic lift.  One parameter is
% exposed that the user can modify in the protected model.
%
% 
% Copyright 2017-2025 The MathWorks, Inc.

%% Model

open_system('ssc_hydraulic_lift')

ann_h = find_system('ssc_hydraulic_lift','MatchFilter',@Simulink.match.allVariants,'FindAll', 'on','type','annotation','Tag','ModelFeatures');
for i=1:length(ann_h)
    set_param(ann_h(i),'Interpreter','off');
end

%% IP Protection
%%
%
% The plots below show the results when a single parameter is varied in the
% protected model.

Hydraulic_Lift_IP_Protect;

%%
close all
bdclose all