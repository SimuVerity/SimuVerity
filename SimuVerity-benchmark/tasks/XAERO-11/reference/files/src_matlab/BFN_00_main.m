% initializes variables for simulink models   %
clc;
clear all;
close all;
addpath('colombo_funs')
addpath('colombo_time')
addpath('funs')


%---------- Select if gyro simplification will be appiled----------
Gyro_Bypass = 1;
Gyro_Bypass_1 = Simulink.Variant('Gyro_Bypass==0');
Gyro_Bypass_2 = Simulink.Variant('Gyro_Bypass==1');
%--------------------------------------------------------------------------

today_mjd2000 = now-7.304865000054932e+05; %Todays data in mjd2000 to make
%every simulation unique

Jsc=[0.0333 0.0838 0.1037];%[kgm2], Spacecraft principle inertia terms

%Targets to point the spacecraft in ECI spherical coords
targets_inertial = [265*pi/180 -29*pi/180;...%milky way center
    2*pi*(18/24+36/24/60+56.34/24/3600) pi/180*(38+47/60+1.29/3600);...%Vega
    2*pi*(2/24+31/24/60+48.70/24/3600) pi/180*(89+15/60+51/3600)...%Polaris
    ];%ecliptical
targets_inertial = spher2car([targets_inertial [1;1;1]]);%ECI cartesian

% loading coefficients for the IGRF13 model
load('sh2020.mat');
agh=[agh,agh41];
dgh=[dgh,dgh41];

m_disturb = [0.01 0.05 0.01]'*0.5e-2;%[Am2] s/c magnetic dipole moment due to
% currents in the s/c
m_max = 1.5; %[Am2] magnetorquer maximum dipole moment
dimensions = [12 24 36]*1e-2;%[m] sc dimensions

%Calculation surfaces normals and positions
Surf_normals = [eye(3) -eye(3)];
Surf_areas = [dimensions(1)*dimensions(2), dimensions(2)*dimensions(3), dimensions(1)*dimensions(3),...
    dimensions(1)*dimensions(2), dimensions(2)*dimensions(3), dimensions(1)*dimensions(3)];
Surf_dist = Surf_normals*0.5.*[dimensions dimensions];
Surf_reflectivity = [5 8 5 5 5 5]*0.1;

%Irradiance
Esun = 1358;%[W/m2] sun radiance
Eearth = (600*0.4+500*0.6+150*0.4+117*0.6);%[W/m2] Earth radiance at 800km (reflected+emitted)
Cd = 2.2;% aerodynamic coeff for flat plate

%-------THRUSTERS-----------------------
MIB = 1e-3;%[Ns] minimum impluse bit
PWM_period = 0.1;%[s]
Tmax = 500e-6;%[N]
Tmin = 10e-6;%[N]
Tnom = 350e-6;%[N]
%Min_impulse = MIB*Tnom; %Ns
Thr_dist = [17 17 17 17 0 0 -17 -17 -17 -17 0 0;...
    0 0 0 0 0 0 0 0 0 0 0 0;...
    0 0 0 0 10 10 0 0 0 0 -10 -10]*1e-2;
Thr_dir = [0 0 0 0 0 0 0 0 0 0 0 0;...
    0 0 1 -1 1 -1 0 0 1 -1 1 -1;...
    1 -1 0 0 0 0 1 -1 0 0 0 0];

%------------SENSORS--------------------------------
Magn_noise = 1.18e-9*sqrt(0.5);
IFEHS_noise = 0.0101e-2*sqrt(0.5);
Gyro_freq = 1e3;%Hz
Gyro_noise_n = 0.01/60*pi/180*sqrt(Gyro_freq);
Gyro_noise_b = 1/3600*pi/180*sqrt(Gyro_freq);

%Initial conditions
w0 = [1 -1 2]'*5*pi/180*0;%[rad/s]
q0 = [-0.3288 -0.3288 -0.3288 0.822]';