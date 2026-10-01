% For detailed user guidance, go to https://github.com/Rchi666/EV_Truck_Model.git
%% Initial Value Setup
clear
clc
Veh_mass = 2885;              % Total mass of vehicle in kilograms
Power_option = 132;         % Three power options available: 95/132/150kW motor
Batt_soc_init = 1;                % Initial state of charge of the battery, set from 0 to 100%
Elec_aux_sw = 1;                 % Switch of auxiliary power consumption
Elec_rgn_sw = 1;                 % Switch of regenerative braking system
Run_number = 1;               % Identifier of run number
testrun = 'REAL';                 % Set simulation test cycle: NEDC/WLTP/CLTC/... Remember to select the test cycle and update simulation time first
Simulink.sdi.view;
Simulink.sdi.clear;
open("EV_Truck_Model.slx");
load("time.mat")                %Load user pre-defined drive profile (time)
load("speed.mat")             %Load user pre-defined drive profile (speed)

%% Run Simulation
Simulink.sdi.view;
Simulink.sdi.clear;
sim("EV_Truck_Model.slx");

%fig = Simulink.sdi.snapshot;
%figfilename = ['REAL_',num2str(Power_option),'kW_Run_',num2str(Run_number),'.png'];
%saveas(fig, figfilename);
