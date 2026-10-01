% DEFINE ALL PARAMETERS FOR Dual_Clutch_Trans Model
% Copyright 2011-2025 The MathWorks, Inc.

T_max=370;  
decimation = 1;
Drive_Cycle_Num = 7;

% 6 SPEED TRANSMISSION
DCT_Param.Transmission.Ratios = [3.78 2.18 1.43 1.03 0.935 0.84];

DCT_Param.Transmission.Shaft_Inertia_Odd = 0.0023;      % kg*m^2
DCT_Param.Transmission.Shaft_Inertia_Even = 0.0009;     % kg*m^2
DCT_Param.Transmission.Shaft_Inertia_Output = 0.008;    % kg*m^2
DCT_Param.Transmission.Gear_Inertia = 0.001;            % kg*m^2
DCT_Param.Transmission.Gear_Efficiency = 0.94;
DCT_Param.Transmission.Gear_Ang_Vel_Thr = 0.01;
DCT_Param.Transmission.Shaft_Velocity_Odd = 0;          % rad/s
DCT_Param.Transmission.Shaft_Velocity_Even = 0;         % rad/s
DCT_Param.Transmission.Shaft_Velocity_Output = 0;       % rad/s
DCT_Param.Transmission.Gear_Initial_Velocity = 0;            % kg*m^2

DCT_Param.Transmission.Abstract.Compliance = 1e5;       
DCT_Param.Transmission.Abstract.Damping = 1e4;
DCT_Param.Transmission.Abstract.Ratio_Time_Const = 0.05;
DCT_Param.Transmission.Abstract.Shift_Gear_Delay = 25; %ms delay

% Ratio_Time_Const = 0.087;
% Shift_Gear_Delay = 31;

% CLUTCH PARAMETERS
DCT_Param.Clutch.Torque_Radius = 130;   % mm
DCT_Param.Clutch.Num_Friction_Surfaces = 4;
DCT_Param.Clutch.Engagement_Piston_Area = 0.001; %m^2

DCT_Param.Clutch.Kinetic_Friction_Coeff = 0.3;
DCT_Param.Clutch.Static_Friction_Coeff = 0.31;
DCT_Param.Clutch.Derating_Factor = 1;
DCT_Param.Clutch.Clutch_Velocity_Tolerance = 0.001; % rad/s
DCT_Param.Clutch.Threshold_Pressure = 1; % Pa
DCT_Param.Clutch.Drag_Torque_Coeff = 0; 

% DOG CLUTCH PARAMETERS
% Friction Clutch Approximation
DCT_Param.Dog_Clutch.Max_Torque = 1000;             % N*m
DCT_Param.Dog_Clutch.Teeth_Mean_Radius = 50;        % N*m

DCT_Param.Dog_Clutch.Tooth_Height = 10;             % N*m
DCT_Param.Dog_Clutch.Ring_Hub_Clearance = 3;        % mm
DCT_Param.Dog_Clutch.Ring_Stop_Stiffness = 1e+6;    % N/m
DCT_Param.Dog_Clutch.Ring_Stop_Damping = 1000;      % N/(m/s)
DCT_Param.Dog_Clutch.Shift_Linkage_Damping = 100;   % N/(m/s)

DCT_Param.Dog_Clutch.Max_Engage_Velocity = 1e6; % rad/s
DCT_Param.Dog_Clutch.Tooth_Engage_Overlap = 3;   % mm


% VEHICLE PARAMETERS
DCT_Param.Vehicle.Mass = 1600;          % kg
DCT_Param.Vehicle.Wheels_Per_Axle = 2;	% kg
DCT_Param.Vehicle.Distance_CG_FrontAxle = 1.7;
DCT_Param.Vehicle.Distance_CG_RearAxle = 2;
DCT_Param.Vehicle.Distance_CG_Ground = 0.5;
DCT_Param.Vehicle.Frontal_Area = 3;	% m
DCT_Param.Vehicle.Aero_Drag_Coeff = 0.4;
DCT_Param.Vehicle.Initial_Velocity = 0;

DCT_Param.Vehicle.Final_Drive_Ratio = 3.7;
DCT_Param.Vehicle.Final_Drive_Efficiency = 0.86;
DCT_Param.Vehicle.Final_Drive_Vel_Thresh = 0.01;
DCT_Param.Vehicle.Side_Shaft_Inertia = 0.01;
DCT_Param.Vehicle.Side_Shaft_Initial_Velocity = 0;

DCT_Param.Vehicle.Tire.Radius = 0.312;          % m
DCT_Param.Vehicle.Tire.Inertia = 0.5;           % kg*m^2
DCT_Param.Vehicle.Tire.Initial_Velocity = 0;	% rpm
DCT_Param.Vehicle.Tire.Slip_Vel_Thresh = 0.1;   % m/s

DCT_Param.Vehicle.Tire.Nominal_Vertical_Load = 4000;   % m/s
DCT_Param.Vehicle.Tire.C_Coeff = 1.685;   
DCT_Param.Vehicle.Tire.D_Coeff = [1.21 -0.037];   
DCT_Param.Vehicle.Tire.E_Coeff = [0.344 0.095 -0.02 0];   
DCT_Param.Vehicle.Tire.BCD_Coeff = [21.51 -0.163 0.245];   
DCT_Param.Vehicle.Tire.H_Coeff = [-0.002 0.002];   
DCT_Param.Vehicle.Tire.V_Coeff = [0 0];   


% INTERNAL COMBUSTION ENGINE (ICE) PARAMETERS
% POLYNOMIAL PARAMETERIZATION
DCT_Param.ICE.Max_Power = 100e3;            % W
DCT_Param.ICE.Speed_At_Max_Power = 5500;    % RPM
DCT_Param.ICE.Max_Speed = 7000;             % RPM
DCT_Param.ICE.Stall_Speed = 200;             % RPM

DCT_Param.ICE.Shaft_Inertia = 0.2;          % kg*m^2
DCT_Param.ICE.Initial_Velocity = 800;       % RPM
DCT_Param.ICE.Idle_Ref_Spd = 800;           % RPM
DCT_Param.ICE.Engine_Time_Constant = 0.2;   % Seconds
DCT_Param.ICE.Initial_Normalized_Throttle = 0; 
DCT_Param.ICE.Speed_Threshold = 20;         % RPM

%DCT_Param.ICE.Friction = 0.2079;           % N*m*s/rad

% FUEL ECONOMY CALCULATION
load FuelConsMap
DCT_Param.ICE.FC.Speed_Vector = FCMap.Speed_Vector;
DCT_Param.ICE.FC.Torque_Vector = FCMap.Torque_Vector;
DCT_Param.ICE.FC.Consumption_Table = FCMap.Consumption_Table;
clear FCMap

% SHIFT MAP, EXAMPLE
DCT_Param.Shift_Map_Example.Pedal_Positions =  [0.1 0.4 0.5 0.9];
DCT_Param.Shift_Map_Example.Upshift_Speeds = ...
   [11.0	20.0	26.0	34.5	43;
    14.0	26.0	35.0	44.5    55;
    17.0	31.0	42.0	52.5	65;
    21.0	39.0	52.0	66.5	80];
DCT_Param.Shift_Map_Example.Downshift_Speeds = ...
   [8.9     17.0	23.6	32.4	40.8;
    11.5	22.7	32.0	41.6	52.2;
    14.0    27.0	38.1	50.0	62.0;
    18.0	33.0	48.0	62.6	76.2];

% SHIFT MAP, DEFAULT VALUES (ORIGINAL)
DCT_Param.Shift_Map_ORIG.Pedal_Positions =  [0.1 0.4 0.5 0.9];
DCT_Param.Shift_Map_ORIG.Upshift_Speeds = ...
   [11.5000   23.5000   35.5000   45.5000   55.5000;
   14.5000   26.5000   38.5000   48.5000   58.5000;
   17.5000   29.5000   41.5000   51.5000   61.5000;
   20.5000   32.5000   44.5000   54.5000   64.5000];
DCT_Param.Shift_Map_ORIG.Downshift_Speeds = ...
   [8.5000   20.5000   32.5000   42.5000   52.5000;
   11.5000   23.5000   35.5000   45.5000   55.5000;
   14.5000   26.5000   38.5000   48.5000   58.5000;
   17.5000   29.5000   41.5000   51.5000   61.5000];

% OPTIMIZED SHIFT SCHEDULE (Abs, Rea, 506)
DCT_Param.Shift_Map_OPT.Pedal_Positions =  [0.1 0.4 0.5 0.9];
DCT_Param.Shift_Map_OPT.Upshift_Speeds = ...
   [17.8469   29.8469   35.8159   41.2981   46.3004;
   19.2469   33.9778   43.9778   53.9778   63.9778;
   24.5469   41.9778   62.1778   78.5778  106.9778;
   27.5469   59.3778   99.0445  109.0445  119.0445];

DCT_Param.Shift_Map_OPT.Downshift_Speeds = ...
   [14.8469   26.8469   32.8159   38.2981   43.3004;
   16.2469   30.9778   40.9778   50.9778   60.9778;
   21.5469   38.9778   59.1778   75.5778  103.9778;
   24.5469   56.3778   96.0445  106.0445  116.0445];

% CHOOSE MAP TO USE AT START
DCT_Param.Shift_Map = DCT_Param.Shift_Map_ORIG;
Upshift_Speeds = DCT_Param.Shift_Map_ORIG.Upshift_Speeds;
Downshift_Speeds = DCT_Param.Shift_Map_ORIG.Downshift_Speeds;
Pedal_Positions = DCT_Param.Shift_Map_ORIG.Pedal_Positions;

% CONTROLLER PARAMETERS
DCT_Param.Control.Clutch.Min_Lock_Pressure = 20e5; % Pa
DCT_Param.Control.Clutch.Max_Lock_Pressure = 50e5; % Pa
DCT_Param.Control.Clutch.Max_Unlock_Pressure = 5e5; % Pa

% DRIVER PARAMETERS
DCT_Param.Driver.Kp = 400; 
DCT_Param.Driver.Ki = 0.001;   
DCT_Param.Driver.Pedal_Filter_Const = 0.01;   

% DOG CLUTCH PARAMETERS
DCT_Param.Dog_Clutches.Pulse_Delay = 50;   % 50*0.01 = 0.5 sec
DCT_Param.Dog_Clutches.Pulse_Length = 20;  % 50*0.01 = 0.5 sec
%DCT_Param.Dog_Clutches.Pulse_Length = 50;  % 50*0.01 = 0.5 sec


% CONTROLLER PARAMETERS
DCT_Param.Control.Engine_Start_RPM = 800; % RPM
DCT_Param.Control.Engine_Stop_RPM = 790; % RPM

DCT_Param.Control.Mode_Logic_TS = 0.1;
DCT_Param.Control.ICE.Kp = 0.02;
DCT_Param.Control.ICE.Ki = 0.01;
DCT_Param.Control.Gen.Kp = 10;
DCT_Param.Control.Gen.Ki = 3;
DCT_Param.Control.Mot.Kp = 500;
DCT_Param.Control.Mot.Ki = 300;
DCT_Param.Control.Veh_Spd.Kp = 0.02;
DCT_Param.Control.Veh_Spd.Ki = 0.04;

% ANIMATION PARAMETERS
DCT_Param.Animation.Teeth_Ratios = [22/65 30/54 44/48 48/50 46/39 50/26];
DCT_Param.Animation.Teeth_Ratios_Reverse = [22/48 21/28];



% ALTERNATE OPTIMIZED SCHEDULE 1 (Det, Desk, 506)
DCT_Param.Shift_Map_OPT506.Pedal_Positions =  [0.1 0.4 0.5 0.9];
DCT_Param.Shift_Map_OPT506.Upshift_Speeds = ...
   [18.0000   30.2000   48.3000   67.3322   77.3429;
   20.1000   36.8500   66.6178   76.7537   86.7537;
   21.1000   40.2500   71.0189   81.0189   91.7873;
   24.1000   63.7500   80.7523  105.9489  115.9489];


DCT_Param.Shift_Map_OPT506.Downshift_Speeds = ...
   [15.0000   27.2000   45.3000   64.3322   74.3429;
   17.1000   33.8500   63.6178   73.7537   83.7537;
   18.1000   37.2500   68.0189   78.0189   88.7873;
   21.1000   60.7500   77.7523  102.9489  112.9489];

% ALTERNATE OPTIMIZED SCHEDULE 2 (Abs Rea 176)
DCT_Param.Shift_Map_OPTAbsRea176.Pedal_Positions =  [0.1 0.4 0.5 0.9];
DCT_Param.Shift_Map_OPTAbsRea176.Upshift_Speeds = ...
   [17.8469   29.8469   35.7875   44.0901   49.4243;
   18.9219   34.1312   45.8256   59.7585   69.7585;
   32.1719   43.4585   53.5100  103.2151  114.6401;
   35.1719   59.2585   99.5217  109.5217  119.5217];
DCT_Param.Shift_Map_OPTAbsRea176.Downshift_Speeds = ...
   [14.8469   26.8469   32.7875   41.0901   46.4243;
   15.9219   31.1312   42.8256   56.7585   66.7585;
   29.1719   40.4585   50.5100  100.2151  111.6401;
   32.1719   56.2585   96.5217  106.5217  116.5217];

