%% Bouncing Ball With Zero Crossings
% 
% This example models a ball bouncing on a floor using the Spatial Contact
% Force block.  MATLAB scripts explore the effect of enabling and disabling
% zero crossings and the effect of solver settings on the simulation
% results.
%
% Copyright 2019-2026 The MathWorks, Inc.



%% Model

open_system('sm_contact_ball')

set_param(find_system('sm_contact_ball','MatchFilter',@Simulink.match.allVariants,'FindAll', 'on','type','annotation','Tag','ModelFeatures'),'Interpreter','off')

%% Simulation Results from Simscape Logging
%%
%
% This plot shows the height of the ball with time. 
%

sm_contact_ball_plot1time;

%% Simulation Results from Simscape Logging: Effect of Zero Crossings
%%
%
% This plot shows the height of the ball with time with zero crossings
% enabled and disabled.
%

set_param('sm_contact_ball/Brick Solid Floor 1','BrickDimensions','[0.5 0.5 1]');
sm_contact_ball_plot2comparezcs;

%% Simulation Results from Simscape Logging: Thin Floor
%%
%
% This plot shows the height of the ball with time if the test is conducted
% with a thin floor.  If the step size is too large, the ball can pass
% through the floor between simulation steps.  Enabling zero-crossings can
% help but may not guarantee the event of the ball hitting the floor will
% always be captured. 
%

set_param('sm_contact_ball/Brick Solid Floor 1','BrickDimensions','[0.5 0.5 0.01]');
set_param('sm_contact_ball','StopTime','20');
sm_contact_ball_plot2comparezcs;
set_param('sm_contact_ball','StopTime','3.25');

%% Simulation Results from Simscape Logging: Thin Floor, Maximum Step Size
%%
%
% This plot shows the height of the ball with time if the test is conducted
% with a thin floor.  If the step size is too large, the ball can pass
% through the floor between simulation steps.  Limiting the maximum step
% size is a better way to ensure the event will be captured.
%

set_param('sm_contact_ball/Brick Solid Floor 1','BrickDimensions','[0.5 0.5 0.01]');
set_param('sm_contact_ball','StopTime','20');
set_param('sm_contact_ball','MaxStep','1e-2');
sm_contact_ball_plot2comparezcs;
subplot(2,1,1)
title('Ball Height, Max Step 1e-2')
set_param('sm_contact_ball','StopTime','3.25');
set_param('sm_contact_ball','MaxStep','1e-1');

%%

%clear all
close all
bdclose all
