% Load parameters for sm_membrane_ball
% Copyright 2021-2026 The MathWorks, Inc.

% Contact parameters
sph_mem_k     = 2e4;
sph_mem_b     = 5e2;
sph_mem_trs_w = 1e-4;

% Define membrane
[grid_x, grid_y, grid_h] = membrane_grid_params(1,[1 1 1]);

% Define spheres
sphere_radius = 0.1;
sphere_ptcld  = Point_Cloud_Data_Sphere(sphere_radius,200);
sphere_half_extr_data =[0 0;cos(0:pi/2/20:pi/2)' sin(0:pi/2/20:pi/2)']*sphere_radius;

% Expression to only use points on half the sphere
%sphere_ptcld_half = sphere_ptcld(sphere_ptcld(:,3)>0,:);

% Parameters for stem
stem_len  = 0.4;
stem_rmax = sphere_radius;
stem_rmin = 0.03;

% Generate point cloud and extrusion for stem
[ptcld_stem, extr_data_stem] = stem_params(stem_len,stem_rmax,stem_rmin);

