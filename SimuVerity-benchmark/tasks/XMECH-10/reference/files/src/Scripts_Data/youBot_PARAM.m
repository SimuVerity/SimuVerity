% Parameters for youBot Arm model
% Copyright 2016-2025 The MathWorks, Inc.

%% Cube and Fixed Payload 
% Cube that moves on belt
YBT_Par.Cube.d = 6e-2;                         % m
YBT_Par.Cube.Con.rSph = YBT_Par.Cube.d*5e-2;   % m
YBT_Par.Cube.init_z = 1e-1; % m Lower surface above floor
YBT_Par.Cube.init_y = 40e-2+20e-2;             % m CG to World
YBT_Par.Cube.mark.base = YBT_Par.Cube.d*0.4;   % m
YBT_Par.Cube.mark.height = YBT_Par.Cube.d*0.7; % m
YBT_Par.Cube.mark.extrusion = [...
    YBT_Par.Cube.mark.base/2 -YBT_Par.Cube.mark.height/2;...
    YBT_Par.Cube.mark.base*0  YBT_Par.Cube.mark.height/2;...
   -YBT_Par.Cube.mark.base/2 -YBT_Par.Cube.mark.height/2]; %m
YBT_Par.Cube.mark.color = [0.0 0.3 0.5];       % RGB

% Payload rigidly attached to gripper for testing
YBT_Par.Payload.max_m   = 0.5;   % kg
% Parameters if payload is a sphere
YBT_Par.Payload.Sph.rad = 0.025; % m
YBT_Par.Payload.Sph.rho = YBT_Par.Payload.max_m/(4/3*pi*YBT_Par.Payload.Sph.rad); % kg/m^3
% Parameters if payload is a cube
YBT_Par.Payload.Cube.d  = YBT_Par.Cube.d; % m
YBT_Par.Payload.Cube.rho = YBT_Par.Payload.max_m/(YBT_Par.Payload.Cube.d^3); % kg/m^3

% Location of end effector reference frame relative to gripper housing
YBT_Par.Payload.gripper_ref_offset = 0.064;

%% Floor
YBT_Par.Floor.r = 54.5e-2; % m
YBT_Par.Floor.d = 1e-2;    % m

%% Power Source
YBT_Par.Battery.v = 24; % V

%% Control Parameters 

% Logic
% Arm
YBT_Par.Control.Logic.Delay_Move_Box = 0.5; % sec
% Gripper
YBT_Par.Control.Logic.Delay_Grip_Box = 3;       % sec
YBT_Par.Control.Logic.Delay_Drop_Box = 3.5;     % sec
YBT_Par.Control.Logic.Delay_Close_Grip = 3;     % sec
% Belt
YBT_Par.Control.Logic.Delay_Belt_Clear = 1;     % sec
YBT_Par.Control.Logic.Delay_Ship_Box = 1.5;     % sec

% Filter constants that approximate actuator dynamics
YBT_Par.Motion_Input_Filter_Const = 0.01;       % sec
YBT_Par.Motion_Input_Filter_Const_Finger = 0.1; % sec

% Dead band in controller
YBT_Par.Control.Dead_Band = 0.1; % deg


%% Belt In
YBT_Par.BeltIn.length = 0.4;  % m
YBT_Par.BeltIn.width  = 0.1;  % m
YBT_Par.BeltIn.height = 0.06; % m
YBT_Par.BeltIn.depth  = 0.02; % m
YBT_Par.BeltIn.spd    = 0.1;  % m/s
YBT_Par.BeltIn.dist_from_robot  = 0.305; % m
YBT_Par.BeltIn.offset = [0 YBT_Par.BeltIn.dist_from_robot+YBT_Par.BeltIn.length/2 YBT_Par.BeltIn.height-YBT_Par.BeltIn.depth/2]; % m
YBT_Par.BeltIn.Control.Delay_on = 0.2;  % sec - perhaps move to logic
YBT_Par.BeltIn.Roller.color = [1 1 1];  % RGB

% Light Curtain Sensor
YBT_Par.BeltIn.Sensor.Beam.radius = 0.0025;  % m
YBT_Par.BeltIn.Sensor.Beam.length = YBT_Par.BeltIn.width*1.5;  % m
YBT_Par.BeltIn.Sensor.Beam.offset = YBT_Par.BeltIn.Sensor.Beam.radius*4; % m
YBT_Par.BeltIn.Sensor.Beam.color  = [1 0 0]; % RGB
YBT_Par.BeltIn.Sensor.Beam.opacity  = 0.5;   % 0 to 1
YBT_Par.BeltIn.Sensor.height = (YBT_Par.BeltIn.depth+YBT_Par.Payload.Cube.d)/2;  % m
YBT_Par.BeltIn.Sensor.x_offset_belt_ctr = 0.12;  % m
YBT_Par.BeltIn.Sensor.offset = [YBT_Par.BeltIn.Sensor.x_offset_belt_ctr 0 YBT_Par.BeltIn.Sensor.height]; % m

%% Belt Out
% Output belt nearly same as input belt
YBT_Par.BeltOut = YBT_Par.BeltIn;

% Minor difference in y-offset for location 
% World not aligned with Robot pivot axis
YBT_Par.BeltOut.offset = [-YBT_Par.BeltOut.dist_from_robot-YBT_Par.BeltOut.length/2 0.006 YBT_Par.BeltOut.height-YBT_Par.BeltOut.depth/2]; %m
YBT_Par.BeltOut.Control.Delay_on = 0.5; % sec - perhaps move to logic

%% Contact parameters for gripper fingers
YBT_Par.Finger.Con.yoffset = 1e-2; % m
YBT_Par.Finger.Con.x = 1e-2;       % m
YBT_Par.Finger.Con.y = 1e-2;       % m
YBT_Par.Finger.Con.z = 5e-4;       % m
YBT_Par.Finger.Con.rSph = 5e-4;    % m    
YBT_Par.Finger.Con.k = 1e4;        % N/m
YBT_Par.Finger.Con.b = 5e1;        % N/(m/s)
YBT_Par.Finger.Con.mus = 0.7;      % 0 - 1 
YBT_Par.Finger.Con.muk = 0.5;      % 0 - 1
YBT_Par.Finger.Con.vth = 1e-3;     % m/s
YBT_Par.Finger.Con.damper = 1e4;   % N/(m/s)

%% Motor parameters
% Maxon EC45 50W  Order Number 251601
% http://www.maxonmotor.com/maxon/view/product/251601
YBT_Par.Pivot.Motor.K = 1/33.5e-3; % A/(N*m)
YBT_Par.Pivot.Motor.R = 0.978;     % Ohm
YBT_Par.Pivot.Motor.L = 0.573e-3;  % H
YBT_Par.Pivot.Motor.gr = 156;      % Gear ratio
YBT_Par.Pivot.Motor.range = [-169 169]*pi/180; % Range of motion, rad
YBT_Par.Pivot.Motor.max_spd = [-90 90]*pi/180; % Max speed, rad/s
YBT_Par.Pivot.Motor.no_load_i = 201e-3;         % A
YBT_Par.Pivot.Motor.friction = 40; % N*m/(rad/s)

% Maxon EC45 50W  Order Number 251601
YBT_Par.Bicep.Motor.K = 1/33.5e-3; % A/(N*m)
YBT_Par.Bicep.Motor.R = 0.978;     % Ohm
YBT_Par.Bicep.Motor.L = 0.573e-3;  % H
YBT_Par.Bicep.Motor.gr = 156;      % Gear ratio
YBT_Par.Bicep.Motor.range = [-65 90]*pi/180;   % Range of motion, rad
YBT_Par.Bicep.Motor.max_spd = [-90 90]*pi/180; % Max speed, rad/s
YBT_Par.Bicep.Motor.no_load_i = 201e-3;        % A
YBT_Par.Bicep.Motor.friction = 40; % N*m/(rad/s)

% Maxon EC45 50W  Order Number 251601
YBT_Par.Forearm.Motor.K = 1/36.9e-3; % A/(N*m)
YBT_Par.Forearm.Motor.R = 0.978;     % Ohm
YBT_Par.Forearm.Motor.L = 0.573e-3;  % H
YBT_Par.Forearm.Motor.gr = 100;      % Gear ratio
YBT_Par.Forearm.Motor.range = [-151 146]*pi/180; % Range of motion, rad
YBT_Par.Forearm.Motor.max_spd = [-90 90]*pi/180; % Max speed, rad/s
YBT_Par.Forearm.Motor.no_load_i = 201e-3;        % A
YBT_Par.Forearm.Motor.friction = 20; % N*m/(rad/s)

% Maxon EC45 30W  Order Number 339281
%http://www.maxonmotor.com/maxon/view/product/339281
YBT_Par.Wrist.Motor.K = 1/51.0e-3;  % A/(N*m)
YBT_Par.Wrist.Motor.R = 4.48;       % Ohm
YBT_Par.Wrist.Motor.L = 2.24e-3;    % H
YBT_Par.Wrist.Motor.gr = 71;        % Gear ratio
YBT_Par.Wrist.Motor.range = [-102 102]*pi/180;   % Range of motion, rad
YBT_Par.Wrist.Motor.max_spd = [-90 90]*pi/180;   % Max speed, rad/s
YBT_Par.Wrist.Motor.no_load_i = 81.4e-3;         % A
YBT_Par.Wrist.Motor.friction = 8;   % N*m/(rad/s)

% Maxon EC32 15W  Order Number 267121
%http://www.maxonmotor.com/maxon/view/product/267121
YBT_Par.Gripper.Motor.K = 1/49e-3;   % A/(N*m)
YBT_Par.Gripper.Motor.R = 13.7;      % Ohm
YBT_Par.Gripper.Motor.L = 7.73e-3;   % H
YBT_Par.Gripper.Motor.gr = 46;       % Gear ratio
YBT_Par.Gripper.Motor.range = [-167 167]*pi/180; % Range of motion, rad
YBT_Par.Gripper.Motor.max_spd = [-90 90]*pi/180; % Max speed, rad/s
YBT_Par.Gripper.Motor.no_load_i = 73.4e-3;       % A
YBT_Par.Gripper.Motor.friction = 20; % N*m/(rad/s)
YBT_Par.Gripper.Position.closed = 0; % m
YBT_Par.Gripper.Position.open   = 35;  % mm
YBT_Par.Gripper.Position.tight  = 29;  % mm

% Maxon EC32 15W  Order Number 267121
% Should be parameterized as a stepper motor, part number unknown
% Modeled as a DC motor for now
YBT_Par.Finger_A.Motor.K = 0.1;      % A/(N*m)
YBT_Par.Finger_A.Motor.R = 13.7;     % Ohm
YBT_Par.Finger_A.Motor.L = 7.73e-3;  % H
YBT_Par.Finger_A.Motor.friction = 1; % N/(m/s)
YBT_Par.Finger_A.Motor.gr = 46;      % Gear ratio
YBT_Par.Finger_A.Motor.max_spd = 35; % mm/s - this is a guess

YBT_Par.Finger_B.Motor.K = 0.1; %m
YBT_Par.Finger_B.Motor.R = 13.7; %m
YBT_Par.Finger_B.Motor.L = 7.73e-3; % H
YBT_Par.Finger_B.Motor.friction = 1; % H
YBT_Par.Finger_B.Motor.gr = 46;     % Gear ratio
YBT_Par.Finger_B.Motor.max_spd = 35; % mm/s

%% Splines 
%  Time vector and revolute joint angles
%  Finger position handled separately to permit
%  independent definition of time vector

% Belt In to Belt Out 
% Manually defined points, linear trajectory
YBT_Par.Waypoints.In2Out.ManualL.t = [...
         0    0.7500    1.5000    2.2500    3.0000];
YBT_Par.Waypoints.In2Out.ManualL.q = [...
         0         0   45.0000   90.0000   90.0000;...
   60.0000         0         0         0  -60.0000;...
  115.0000   58.7500    2.5000  -53.7500 -110.0000;...
  -85.0000  -44.0000   -3.0000   38.0000   80.0000;...
         0         0         0         0         0];

% Belt In to Belt Out 
% Manually defined points, tuned for cubic spline
YBT_Par.Waypoints.In2Out.Manual.t = [...
         0    0.7500    1.5000    2.2500    3.0000];
YBT_Par.Waypoints.In2Out.Manual.q = [...
        0    7.0000   45.0000   83.0000   90.0000;...
   60.0000   10.0000         0  -10.0000  -60.0000;...
  115.0000   58.7500    2.5000  -53.7500 -110.0000;...
  -85.0000  -44.0000   -3.0000   38.0000   80.0000;...
         0         0         0         0         0];
     
% Belt In to Belt Out
% Points found via optimization during low friction test
% Tuned for cubic spline
YBT_Par.Waypoints.In2Out.OptNoFriction.t = [...
         0    0.7500    1.5000    2.2500    3.0000];
YBT_Par.Waypoints.In2Out.OptNoFriction.q = [...
         0   -5.8000   19.4000   79.8000   90.0000;...
   60.0000  -34.8000   -0.8000   33.2000  -60.0000;...
  115.0000  141.9500    2.5000 -141.7500 -110.0000;...
  -85.0000 -101.6000   -3.0000  101.2000   80.0000;...
         0         0         0         0         0];
     
% Belt In to Belt Out
% Points found via optimization during high friction test
% Tuned for cubic spline
YBT_Par.Waypoints.In2Out.OptFriction.t = [...
         0    0.7500    1.5000    2.2500    3.0000];
YBT_Par.Waypoints.In2Out.OptFriction.q     = [...
         0   22.6000   45.0000   67.4000   90.0000;...
   60.0000   30.8000    2.0000  -27.8000  -60.0000;...
  115.0000   60.3500    6.1000  -50.1500 -110.0000;...
  -85.0000  -36.8000    7.8000   47.6000   80.0000;...
         0         0         0         0         0];

% Home to Belt In
% Parameters to generate linear trajectory
YBT_Par.Waypoints.Home.q = zeros(1,5);
YBT_Par.Waypoints.Home2In.Duration = 2;
YBT_Par.Waypoints.Home2In.numpts = 5;

% Home to Belt In
% Linear trajectory
YBT_Par.Waypoints.Home2In.Manual.t = [...
         linspace(0,YBT_Par.Waypoints.Home2In.Duration,...
         YBT_Par.Waypoints.Home2In.numpts)];
YBT_Par.Waypoints.Home2In.Manual.q = [...
         zeros(1,YBT_Par.Waypoints.Home2In.numpts);...
         linspace(0,60,YBT_Par.Waypoints.Home2In.numpts);...
         linspace(0,115,YBT_Par.Waypoints.Home2In.numpts);...
         linspace(0,-85,YBT_Par.Waypoints.Home2In.numpts);...
         zeros(1,YBT_Par.Waypoints.Home2In.numpts)];
     
% Belt Out to Home
% Parameters to generate linear trajectory
YBT_Par.Waypoints.Out2Home.Duration = 2.5;
YBT_Par.Waypoints.Out2Home.numpts = 5;

% Belt Out to Home
% Linear trajectory
YBT_Par.Waypoints.Out2Home.Manual.t = [...
         linspace(0,YBT_Par.Waypoints.Out2Home.Duration,...
         YBT_Par.Waypoints.Out2Home.numpts)];
YBT_Par.Waypoints.Out2Home.Manual.q = [...
          90.0000   67.5000   45.0000   22.5000 0;...
         -60.0000  -45.0000  -30.0000  -15.0000 0;...
        -110.0000  -82.5000  -55.0000  -27.5000 0;...
          80.0000   60.0000   40.0000   20.0000 0;...
         zeros(1,YBT_Par.Waypoints.Out2Home.numpts)];

% Non-structured parameters - used during optimization
t  = YBT_Par.Waypoints.In2Out.OptFriction.t;
Qt = YBT_Par.Waypoints.In2Out.OptFriction.q;

% Load bus object - used for unit test of Stateflow logic
load Belts_BusObject.mat

