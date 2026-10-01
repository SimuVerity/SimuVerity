%% Ball on Grid Surface
% 
% This example models contact between spheres and a grid surface.  The
% geometry of the sphere is modeled as a point cloud and the surface is
% modeled using the Grid Surface block.
%
% Copyright 2021-2026 The MathWorks, Inc.



%% Model

open_system('sm_membrane_ball')

set_param(find_system('sm_membrane_ball','MatchFilter',@Simulink.match.allVariants,'FindAll', 'on','type','annotation','Tag','ModelFeatures'),'Interpreter','off')

%%
%
% <<sm_membrane_ball_mechExpAnim_membr1.png>>
%

%% Simulation Results from Simscape Logging: Membrane (1), 100 points
%
% Plot ball velocities as the ball falls on the first eigenfunction of the
% L-shaped membrane.  100 points are used for the point cloud.
%

[grid_x, grid_y, grid_h] = membrane_grid_params(1,[1 1 1]);
sphere_ptcld  = Point_Cloud_Data_Sphere(sphere_radius,100);
sim('sm_membrane_ball');
sm_membrane_ball_plot1ballvel;

%% Simulation Results from Simscape Logging: Membrane (1), 200 points
%
% Plot ball velocities as the ball falls on the first eigenfunction of the
% L-shaped membrane.  100 points are used for the point cloud.
%

[grid_x, grid_y, grid_h] = membrane_grid_params(1,[1 1 1]);
sphere_ptcld  = Point_Cloud_Data_Sphere(sphere_radius,200);
sim('sm_membrane_ball');
sm_membrane_ball_plot1ballvel;

%% Simulation Results from Simscape Logging: Membrane (6), 200 points
%
% Plot ball velocities as the ball falls on the first eigenfunction of the
% L-shaped membrane.  100 points are used for the point cloud.
%

[grid_x, grid_y, grid_h] = membrane_grid_params(6,[1 1 1]);
sphere_ptcld  = Point_Cloud_Data_Sphere(sphere_radius,200);
sim('sm_membrane_ball');
sm_membrane_ball_plot1ballvel;

%% Simulation Results from Simscape Logging: Membrane (6), 200 points, Short Stem
%
% Plot ball velocities as the ball falls on the first eigenfunction of the
% L-shaped membrane.  100 points are used for the point cloud.
%

[grid_x, grid_y, grid_h] = membrane_grid_params(6,[1 1 1]);
sphere_ptcld  = Point_Cloud_Data_Sphere(sphere_radius,200);
stem_len = 0.2;
[ptcld_stem, extr_data_stem] = stem_params(stem_len,stem_rmax,stem_rmin);

sim('sm_membrane_ball');
sm_membrane_ball_plot1ballvel;


%%

%clear all
close all
bdclose all
