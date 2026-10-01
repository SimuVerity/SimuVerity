%% Gripper with Conveyor Belts
%
% This example models a box transported on conveyor belts and a robot
% gripper. It shows how to use a custom contact force law to model how the
% belt pushes the box along the belt.  Another custom force is used for the
% gripper, where a very stiff damper holds the box in the gripper when it
% is close enough for contact.
%
% Copyright 2025-2026 The MathWorks, Inc.


%% Model
%
% <matlab:open_system('Gripper_2Belts'); Open Model>

open_system('Gripper_2Belts')

set_param(find_system('Gripper_2Belts','MatchFilter',@Simulink.match.allVariants,'FindAll', 'on','type','annotation','Tag','ModelFeatures'),'Interpreter','off')

%% Spatial Contact Force block
%
% This subsystem shows the connection between the Spatial Contact Force
% block and the custom force law subsystem.  The Spatial Contact Force
% measures quantities necessary to calculate the normal and friction
% forces.  Those forces are fed back to the Spatial Contact Force block and
% applied to the mechanism.
%
% <matlab:open_system('Gripper_2Belts');open_system('Gripper_2Belts/Force%20Box%20to%20Belt%20Out','force'); Open Subsystem>

set_param('Gripper_2Belts/Force Box to Belt Out','LinkStatus','none');
open_system('Gripper_2Belts/Force Box to Belt Out','force');

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
% <matlab:open_system('Gripper_2Belts');open_system('Gripper_2Belts/Force%20Box%20to%20Belt%20Out/Custom%20Force%20Law','force'); Open Subsystem>

set_param('Gripper_2Belts/Force Box to Belt Out/Custom Force Law','LinkStatus','none');
open_system('Gripper_2Belts/Force Box to Belt Out/Custom Force Law','force');

%% Simulation Results from Simscape Logging
%%
%
% The plot below shows the path of the box as it drops, moves along each
% belt, and is transferred between the belts by the gripper.
%

sim('Gripper_2Belts')
Gripper_2Belts_plot1boxposition;

%%
%clear all
close all
bdclose all
