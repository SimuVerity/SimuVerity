% Parameters for sm_tread_drive
% Copyright 2017-2026 The MathWorks, Inc.

%% Tread geometry
belt.w = 0.6;
belt.l = 2.8;
belt.h = belt.l/4;
belt.m = 0.5; % kg
roller.rad = belt.h/2*0.8;
roller.rho = 1000; % kg/m^3
belt.rad = roller.rad*1.05;
belt.xlen = 0.25;
belt.clr = [0.95 0.95 0.6];
roller.clr = [1 1 1]*0.8;
vehbody.tracksep = 1.8;
vehbody.mass = 600;

tread_extr = Extr_Data_TriangleRounded_Holes(...
    belt.l,belt.h,belt.xlen,0,belt.rad);

% Ground contact force
belt.ground.k   = 5e6*0+2e5;
belt.ground.b   = 1e7*0+1e3*10;
belt.ground.twd  = 1e-2;

% Tread friction force
belt.ground.muk = 0.7*0+0.3;
belt.ground.mus = 0.9*0+0.5;
belt.ground.vth = 0.001*0+0.05;

%% Vehicle initial position
vehbody.x0 = -5;
vehbody.z0 = 0.2;

%% Tread point cloud parameters
tread_outline_npts = 30;
max_height_ptcld = -0.29;
num_lines_along_tread = 3;

% Obtain line of points surrounding track
tread_outline = resampleConvexHull(tread_extr, tread_outline_npts);

% Replicate line across track
tread_ptcld_full = [];
latPosIntv = belt.w/(num_lines_along_tread-1);
for i = 1:num_lines_along_tread
    latPos = -belt.w/2+(i-1)*latPosIntv;
    tread_ptcld_full = [tread_ptcld_full;...
        tread_outline ones(tread_outline_npts,1)*latPos];
end

% Eliminate points above a certain height that will never touch the ground
tread_ptcld_inds = find(tread_ptcld_full(:,2)<=max_height_ptcld);
tread_ptcld = tread_ptcld_full(tread_ptcld_inds,:);

% Reassign so point height is third column
tread_ptcld_y = tread_ptcld(:,3);
tread_ptcld_z = tread_ptcld(:,2);
tread_ptcld(:,2) =  tread_ptcld_y;
tread_ptcld(:,3) =  tread_ptcld_z;

belt.ptcld.pts = tread_ptcld;
belt.ptcld.rad = 2e-2;
belt.ptcld.clr = [0 0 1];
belt.ptcld.outline = tread_outline;

%% Scene parameters
Scene.Terrain = stl_to_gridsurface('hills_terrain.stl',100,100,'n');
Camera =  sm_car_define_camera_sedan;