%  ** conventional airplane parameters **

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2020-2022 Yannic Beyer
%   Copyright (C) 2022 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

% mass, kg
airplane.body.m = 2.15;
% inertia matrix, kg*m^2
airplane.body.I = [ ...
        0.165, -0.0002, -0.008; ...
        -0.0002, 0.177, 0.0003; ...
        -0.008, 0.0003, 0.338 ...
        ];

% center of gravity in c frame, m
airplane.config.cg = [-0.445;0;0];
% collision points in c frame, m
airplane.config.hitPoints = [ [0;0;0],[-1.08;0;0],[-0.44;-0.9075;0],[-0.44;0.9075;0],...
    [-0.1;0;0.05],[-0.95;0;0.05],[-0.25;0;-0.075],[-1;0;-0.26],...
    [-1;-0.22;-0.05],[-1;0.22;-0.05] ];

% aerodynamics parameters
airplane.aero = conventionalAirplaneAeroLoadParams( ...
    'airplaneAeroSimple_params_Funray' );

% propeller parameters
airplane.prop = propMapLoadParams( 'propMap_params_Funray' );

% propeller configuration parameters
airplane.prop.config.Pos = [0;0;0];
airplane.prop.config.Rot = euler2Dcm(deg2rad([0 0 0]));

% motor parameters
airplane.motor = loadParams( 'motorBldc_params_Funray' );

% actuator parameters
airplane.act.ailerons = loadParams('actuatorsPt2_params_Funray');
airplane.act.ailerons.deflectionMax = deg2rad(28);
airplane.act.ailerons.deflectionMin = -deg2rad(28);
airplane.act.elevator = loadParams('actuatorsPt2_params_Funray');
airplane.act.elevator.deflectionMax = deg2rad(21);
airplane.act.elevator.deflectionMin = -deg2rad(21);
airplane.act.rudder = loadParams('actuatorsPt2_params_Funray');
airplane.act.rudder.deflectionMax = deg2rad(27);
airplane.act.rudder.deflectionMin = -deg2rad(27);
airplane.act.htpTrim = loadParams('actuatorsPt2_params_Funray');
airplane.act.htpTrim.deflectionMax = deg2rad(2.51);
airplane.act.htpTrim.deflectionMin = deg2rad(2.49);

% battery parameters
airplane.bat = loadParams( 'battery_params_Funray' );

% cmd struct/bus
num_flaps = length(airplane.aero.wingMain.flap.y_cp_wing)/2;
airplane.cmd = struct('aileron_left',0.5*ones(1,num_flaps),'aileron_right',0.5*ones(1,num_flaps),'elevator',0.5,'rudder',0.5,'throttle',0,'htp_trim',0.5);
struct2slbus(airplane.cmd,'cmd');

% reference position
airplane.posRef = loadParams( 'flightgearRefPos_params_default' );

% ground contact parameters
airplane.grnd = groundLoadParams( 'params_ground_default' );

%% initial conditions (IC)
% kinematic rotational velocity, rad/s
airplane.ic.omega_Kb = zeros(3,1);
% quaternion attitude from NED to body frame
airplane.ic.q_bg = [1;0;0;0];
% kinematic velocity in body frame, m/s
airplane.ic.V_Kb = [0;0;0];
% NED position relative to posRef, m
airplane.ic.s_Kg = [0; 0; 0];
% motor angular velocity, rad/s
airplane.ic.motor_speed = 0;