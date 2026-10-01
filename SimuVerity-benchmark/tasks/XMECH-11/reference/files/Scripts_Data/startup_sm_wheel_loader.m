% Load parameters for wheel loader and CVT models

% Copyright 2023-2025 The MathWorks, Inc.

sm_wheel_loader_params
web('Wheel_Loader_Design_Overview.html');

%% Load cylinder trajectories
load('sm_wheel_loader_test_cylinder_traj.mat');

% Add toothbar trajectory
Toothbar.t          = [0 13 15.5 18 20 57 59 60 62 70]';
Toothbar.p          = [0 0  1     1  0 0  1  1  0  0]'*-73.565;
testInput.BucketYCycle.Toothbar    = Toothbar;
testInput.BucketYCycle.Toothbar.p  = Toothbar.p*0;
testInput.GrappleLogCycle.Toothbar = Toothbar;
clear Toothbar

bucketLoad.t = [0 15.8 17.0 54.0 57.5 70]';
bucketLoad.z = [0 0     1    1    0   0]'*0.5;
testInput.GrappleLogCycle.bucketLoad   = bucketLoad;
testInput.GrappleLogCycle.bucketLoad.z = bucketLoad.z*0;
testInput.BucketYCycle.bucketLoad      = bucketLoad;
clear bucketLoad

testInput.Active = testInput.BucketYCycle;

%% Load Operator Commands
load('sm_wheel_loader_test_operator_cmd.mat')
