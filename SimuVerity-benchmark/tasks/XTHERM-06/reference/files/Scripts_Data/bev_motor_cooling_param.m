% Key parameters for bev_motor_cooling.slx
% Copyright 2021-2025 The MathWorks, Inc.

% Vehicle
bev.car.mass             = 3500; % kg
bev.car.tire.rad         = 33;   % cm
bev.car.gear.rat         = 10;
bev.car.drag.brk         = 750;  % N
bev.car.drag.vth         = 0.1;  % m/s
bev.car.drag.fcl         = 500;  % N
bev.car.drag.cvs         = 30;   % N/(m/s)

% Road
bev.road.slope           = 0.06; % percent
bev.road.gforce          = -9.81*bev.car.mass*sin(atan(bev.road.slope)); % N

% Motor
bev.motor.maxtrq         = 800;    % N*m
bev.motor.maxpwr         = 500e3;  % kW
bev.motor.tc             = 0.02;   % s
bev.motor.eff            = 90;     % percent
bev.motor.w_eff          = 10e3;   % rpm
bev.motor.T_eff          = 400;    % N*m
bev.motor.Piron          = 0;      % W
bev.motor.Pbase          = 0;      % W
bev.motor.Res            = 1e-3;   % Ohm
bev.motor.J              = 0.03;   % kg m^2 
bev.motor.lam            = 1e-5;   % N*m/(rad/s)
bev.motor.speed0         = 0;      % rpm
bev.motor.alpha          = 3.93e-3;% 1/K
bev.motor.Tmeas          = 50;     % degC
bev.motor.thermal_mass   = 8350;   % J/K
bev.motor.initT          = 100;    % degC

bev.motor.qcond.area     = 0.75;   % m^2
bev.motor.qcond.thick    = 0.135;  % m winding thickness
bev.motor.qcond.th_cond  = 392;    % W/(m*K)

% Casing
bev.casing.qconv.area    = 0.75;   % m^2
bev.casing.qconv.th_conv = 1/(1/5 + 1/(240/0.07));     
                                   % W/(m^2 * K) convection + case in series
bev.casing.initT         = 100;    % degC
bev.casing.mass          = 150*0.9;% kg
bev.casing.sp_heat       = 900;    % J/kg/K

% Battery
bev.battery.volt         = 800;    % volts

% Cooling
bev.cooling.area         = 3*pi*0.01^2; % m^2
bev.cooling.hd           = 2*0.01;      % m

bev.tank.vol             = 0.005; % m^3
bev.tank.csec            = 0.04;  % m^2
bev.tank.volInit         = 0.004; % m^3

bev.Tambient             = 45;    % degC

Cooling_On  = 1; % Include cooling system in simulation 
                 % Set to 0 to exclude
