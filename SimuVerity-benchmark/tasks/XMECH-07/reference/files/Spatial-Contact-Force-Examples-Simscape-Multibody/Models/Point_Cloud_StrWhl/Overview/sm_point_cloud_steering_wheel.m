%% Multibody Point Cloud Contact Steering Wheel
% 
% This example models collisions between parameterized solids, solids
% represented by CAD geometry, and point clouds which act as an
% approximation of the geometry for the purpose of contact.  
% 
% Two spheres follow different trajectories as they collide with the
% steering wheel.  The sphere whose contact is directly with the CAD
% geometry follows a path around the convex hull that encloses the CAD
% geometry.  The sphere colliding with the point cloud passes through the
% hole in the steering wheel.
%
% Copyright 2021-2026 The MathWorks, Inc.



%% Model

open_system('sm_point_cloud_steering_wheel')

set_param(find_system('sm_point_cloud_steering_wheel','MatchFilter',@Simulink.match.allVariants,'FindAll', 'on','type','annotation','Tag','ModelFeatures'),'Interpreter','off')


%% Convex Hull 
%
% The Spatial Contact Force block uses a convex hull to detect contact
% between the steering wheel geometry and other objects (ball, floor).
% This plot shows what that convex hull would look like.
%
sm_convex_hull_stlgeometry('steering_wheel_ctr.stl','none','plot')

%% Simulation Results from Simscape Logging
%%
%
% This script plots the paths of the balls and the final position of the
% steering wheel.  The ball that models contact with the STL file directly
% encounters the convex hull and does not pass through the hole.  The ball
% that models contact with the point cloud passes through the hole in the
% steering wheel.
%


sm_point_cloud_steering_wheel_plot1xyz;

%%

%clear all
close all
bdclose all
