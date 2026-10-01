%% Ball on Conveyor
%
% This example models a ball resting on a moving conveyor belt. It shows
% how to use a custom contact force law to model how the belt pushes the
% ball on the belt.  This simple example shows that the custom forces are
% applied correctly even as the reference frame for the ball rotates.
%
% Copyright 2025-2026 The MathWorks, Inc.

%% Model
%
% <matlab:open_system('ball_on_conveyor'); Open Model>

open_system('ball_on_conveyor')

set_param(find_system('ball_on_conveyor','MatchFilter',@Simulink.match.allVariants,'FindAll', 'on','type','annotation','Tag','ModelFeatures'),'Interpreter','off')

%% Spatial Contact Force block
%
% This subsystem shows the connection between the Spatial Contact Force
% block and the custom force law subsystem.  The Spatial Contact Force
% measures quantities necessary to calculate the normal and friction
% forces.  Those forces are fed back to the Spatial Contact Force block and
% applied to the mechanism.
%
% <matlab:open_system('ball_on_conveyor');open_system('ball_on_conveyor/Belt%20to%20Ball%20Force','force'); Open Subsystem>

set_param('ball_on_conveyor/Belt to Ball Force','LinkStatus','none');
open_system('ball_on_conveyor/Belt to Ball Force','force');

%% Custom Contact Force Law
%
% This subsystem shows the implementation of the custom force law.  The
% separation distance and separation velocity are used to calculate the
% normal force.  The tangential velocity and the normal force are used to
% calculate the friction force.
%
% This custom force law lets the user specify the speed of the belt as an
% input signal.  This implementation adds this relative velocity to the
% measured tangential velocity. The resulting friction force will push the
% object as if the solid representing the belt was moving.
% 
% The belt speed is defined along the positive x-axis of the belt, which is
% connected to the Base frame of the Spatial Contact Force block.  Since
% the contact frame may not be aligned with the base geometry reference
% frame, we need a rotation matrix provided by the Spatial Contact Force
% block to transform the velocity expressed in the belt frame to the
% contact force frame.  That velocity is then added to the measured
% tangential velocity components which are measured in the contact force
% frame.
%
% <matlab:open_system('ball_on_conveyor');open_system('ball_on_conveyor/Belt%20to%20Ball%20Force/Custom%20Force%20Law','force'); Open Subsystem>

set_param('ball_on_conveyor/Belt to Ball Force/Custom Force Law','LinkStatus','none');
open_system('ball_on_conveyor/Belt to Ball Force/Custom Force Law','force');

%% Simulation Results from Simscape Logging
%%
%
% The plot below examines the tangential speed of the ball, the conveyor,
% and the friction force.  When the ball is rolling without slipping,
% almost no friction force is applied.  During periods of acceleration and
% deceleration, a friction force is measured.
%

sim('ball_on_conveyor')
ball_on_conveyor_plot1vtang;

%%
%clear all
close all
bdclose all
