% Parameters for sm_tippe_top.slx
% Copyright 2022-2026 The MathWorks, Inc.

scale_factor       = 0.02;     % Scales radii, stem length

% Size of top body
min_angle = -45;  % Angle where sphere is truncated (deg)
head_angular_sweep = min_angle:1:90;

% Size of hollow inside sphere
head_hollow_rad    = 0.8;  % m
head_hollow_depth  = 0.35; % Depth from sphere center towards top

% Derive profile for truncated sphere
head_hollow_x      = min(head_hollow_rad,cosd(head_angular_sweep(1)+eps));
rev_profile_head = [...
    cosd(head_angular_sweep) 0             head_hollow_x ; 
    sind(head_angular_sweep) head_hollow_depth head_hollow_depth ]'*scale_factor;

% Shaft parameters
shaft_radius = 0.2*scale_factor;
shaft_length = 1.5*scale_factor;

top_density = 7000; % kg/m^3

% Height of top, used to define camera and initial height 
top_height = shaft_radius+shaft_length+max(max(rev_profile_head));

% Contact parameters
top_contact_k = 1e6*scale_factor;  % N/m
top_contact_d = 1e4*scale_factor;  % N/(m/s)
top_contact_w = 1e-4; % m

top_friction_s = 0.5;  % (0-1)
top_friction_d = 0.3;  % (0-1)
top_friction_v = 1e-3; % m/s

% Small amount of viscous damping (wind resistance)
% Applied at spherical joint
top_viscous_damping = 1e-8; % N*m/(deg/s)

% Initial conditions
init_angle_x = 150; % deg
init_speed   = [0 0 50]; % rev/sec


% To regenerate point cloud, use this command - takes a few minutes
%ptcld_sphere_rad1_pts1000 = Point_Cloud_Data_Sphere(1,1000,'none');
%ptcld_sphere_rad1_pts200 = Point_Cloud_Data_Sphere(1,200,'none');
%save ptcld_spheres ptcld_sphere_rad1_pts200 ptcld_sphere_rad1_pts1000

% Complete point cloud for convex hull
ptcld_head = ptcld_sphere_rad1_pts1000*max(max(rev_profile_head));
ptcld_base = ptcld_sphere_rad1_pts200*shaft_radius-[0 0 shaft_length];
ptcld_cvh = [ptcld_base;ptcld_head];

