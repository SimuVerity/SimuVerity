% Load parameters for wheel loader model

% Copyright 2023-2025 The MathWorks, Inc.

% Stop time for load cycle
stopTime = 70;

% Vehicle parameters
HMPST = sm_wheel_loader_params_cvt;

% Steering and implement hydraulic parameters
HydFcnParams = sm_wheel_loader_params_hydr;

% Ground contact settings, single sphere per wheel
HMPST.Tire.Contact.sphere.stiffness = 1e5*3; % N/m
HMPST.Tire.Contact.sphere.damping = 5e3*3*10; % N/(m/s)
HMPST.Tire.Contact.sphere.transRegWidth = 1e-2; % m
HMPST.Tire.Contact.sphere.muStatic = 0.6;
HMPST.Tire.Contact.sphere.muDynamic = 0.50;
HMPST.Tire.Contact.sphere.velThreshold = 1e-1; % m/s

% Ground contact settings, tire point cloud
HMPST.Tire.Contact.ptcld.stiffness = 1e5/10; % N/m
HMPST.Tire.Contact.ptcld.damping = 5e3/10; % N/(m/s)
HMPST.Tire.Contact.ptcld.transRegWidth = 1e-2; % m
HMPST.Tire.Contact.ptcld.muStatic = 0.6;
HMPST.Tire.Contact.ptcld.muDynamic = 0.50;
HMPST.Tire.Contact.ptcld.velThreshold = 1e-1; % m/s

% Contact, Log to Surface
logLoad.Contact.Surface.stiffness = 1e5*3; % N/m
logLoad.Contact.Surface.damping = 5e3*3*10; % N/(m/s)
logLoad.Contact.Surface.transRegWidth = 1e-2; % m
logLoad.Contact.Surface.muStatic = 0.6;
logLoad.Contact.Surface.muDynamic = 0.50;
logLoad.Contact.Surface.velThreshold = 1e-1; % m/s

% Contact, Log to Base
logLoad.Contact.Base.stiffness = 1e5*3; % N/m
logLoad.Contact.Base.damping = 5e3*3*10; % N/(m/s)
logLoad.Contact.Base.transRegWidth = 1e-2; % m
logLoad.Contact.Base.muStatic = 0.6;
logLoad.Contact.Base.muDynamic = 0.50;
logLoad.Contact.Base.velThreshold = 1e-1; % m/s

% Contact, Log to Bin
logLoad.Contact.Bin.stiffness = 1e5*3; % N/m
logLoad.Contact.Bin.damping = 5e3*3*10; % N/(m/s)
logLoad.Contact.Bin.transRegWidth = 1e-2; % m
logLoad.Contact.Bin.muStatic = 0.6;
logLoad.Contact.Bin.muDynamic = 0.50;
logLoad.Contact.Bin.velThreshold = 1e-1; % m/s

% Contact, Log to ground
logLoad.Contact.Grapple.stiffness = 1e6/100; % N/m
logLoad.Contact.Grapple.damping = 1e3; % N/(m/s)
logLoad.Contact.Grapple.transRegWidth = 1e-4*100; % m
logLoad.Contact.Grapple.muStatic = 0.5;
logLoad.Contact.Grapple.muDynamic = 0.3;
logLoad.Contact.Grapple.velThreshold = 1e-3*100; % m/s

%% Terrain
Scene.Terrain = stl_to_gridsurface('hills_terrain.stl',100,100,'n');

%% Tire Point Cloud - needs transforms from CAD import
load('sm_wheel_loader_params_CAD_struct.mat')

Wheel_Loader.Extras.bodyGroups(1).visualProperties.opacity = 1; % Seat Trim;
Wheel_Loader.Extras.bodyGroups(2).visualProperties.opacity = 1; % Seat Trim;

HMPST.Tire.ptcld = sm_wheel_loader_params_ptclds_tire;

% Generate point cloud matrices for contact modeling between the wooden log
% and grapple rake and grapple toothbars
HMPST.Grapple.ptcld = sm_wheel_loader_params_ptclds_grapple();

% Base blocks for wooden log - contact point cloud generation
xx = -0.175:0.05:0.175; % Create even number of points in x
yy = -0.1:0.1:0.1;
logLoad.Base.ptcld = zeros(numel(xx)*numel(yy),3);
for nx = 1:numel(xx)
    for ny = 1:numel(yy)
        idx = (nx-1)*numel(yy) + ny;
        logLoad.Base.ptcld(idx,1) = xx(nx);
        logLoad.Base.ptcld(idx,2) = yy(ny);
    end
end
clearvars xx yy nx ny idx

% Wooden log parameters
logLoad.rad = 0.15; % m
logLoad.len = 3.6; % m

logLoad.YCycle.basePos = [7.15 -6.5 0]; % m
logLoad.YCycle.baseOri = -10; % deg
logLoad.YCycle.binPos = [-7.15-0.4 -6.5-0.4-0.4 0]; % m
logLoad.YCycle.binOri = 15; % deg

logLoad.LinkTest.basePos = [0 -4 0]; % m
logLoad.LinkTest.baseOri = 90; % deg
logLoad.LinkTest.binPos = [0 -6 0]; % m
logLoad.LinkTest.binOri = 90; % deg


% Load actuator motion data
%inertiaLoadBucket.t = [0 15.8 17.0 54.0 57.5 70];
%inertiaLoadBucket.z = [0 0     1    1    0   0]*0.5;
%Toothbar.t          = [0 13 15.5 18 20 57 59 60 62];
%Toothbar.p          = [0 0  1     1  0 0  1  1  0]*-73.565;




