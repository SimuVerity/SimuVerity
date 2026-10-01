clear all
close all
clc

%% Environment Setup
% Configures MATLAB to use a specific Python environment

% For Windows users
% Replace 'your_path\your_environment\Scripts\python.exe' with the actual
% path on your machine.

env = pyenv('Version', ...
    'your_path\your_environment\Scripts\python.exe');


% For Linux/macOS users
% Replace '<python-environment>/bin/python' with the
% actual path on your machine.

% env = pyenv('Version', ...
%    '<python-environment>/bin/python');

%% Instantiate a Patient Object

% Imports the Python module containing the simulator.
simulator =...
    py.importlib.import_module('python_anesthesia_simulator.simulator');

% Define patient parameters
age = 18;                   % years
height = 170;               % cm
weight = 60;                % kg
sex = 0;                 % 0 = female, 1 = male
sampling_time = 1;          % seconds

% Creates a patient object with specified parameters
George = simulator.Patient([age, height, weight, sex],...
    ts = sampling_time);

%% Simulation setup

% Defines the total simulation time and calculates the number of simulation
% steps according to the sapling time
T_simu = 3600;                        % total simulation time in seconds
N_simu = floor(T_simu/sampling_time); % total number of simulation steps


% Initialize infusion profiles for propofol and remifentanil
propofol_infusion_profile = zeros(N_simu,1);        % mg/s
remifentanil_infusion_profile = zeros(N_simu,1);    % ug/s

% Propofol profile
propofol_infusion_profile(1:floor(50/sampling_time)) = ...
    2;           % 2 mg/s for 50 seconds
propofol_infusion_profile(floor(121/sampling_time):end) = ...
    0.2;      % 0.2 mg/s from 121s onward

% Remifentanil profile
remifentanil_infusion_profile(1:floor(30/sampling_time)) = ...
    1;       % 1 ug/s for 30 seconds
remifentanil_infusion_profile(floor(121/sampling_time):end) = ...
    0.1;  % 0.1 ug/s from 121s onward

%% Run the simulation

% Executes the simulation
df = George.full_sim(u_propo = propofol_infusion_profile,...
    u_remi = remifentanil_infusion_profile);

% Convert the Python DataFrame to a MATLAB table
George_tbl = table(df);

%% Plotting results

% Effect site concentrations and infusion rates
figure
subplot(2,1,1)
plot(George_tbl.Time, George_tbl.x_propo_4,...
    'DisplayName', 'Propofol [ug/ml]') 
hold on
plot(George_tbl.Time, George_tbl.x_remi_4,...
    'DisplayName', 'Remifentanil [ng/ml]')
xlabel('Time [s]')
ylabel('Effect Site Concentration')
legend('Location','southeast')
grid on
title('Effect site concentrations and infusion rates')

subplot(2,1,2)
plot(George_tbl.Time, George_tbl.u_propo,...
    'DisplayName', 'Propofol [mg/s]')
hold on
plot(George_tbl.Time, George_tbl.u_remi,...
    'DisplayName', 'Remifentanil [ug/s]')
ylabel('Infusion Rate')
legend('Location','northeast')
grid on



% Physiological responses
figure
subplot(4,1,1)
plot(George_tbl.Time, George_tbl.BIS)
ylabel('BIS')
grid on
title('Physiological responses')

subplot(4,1,2)
plot(George_tbl.Time, George_tbl.MAP)
ylabel('MAP')
grid on

subplot(4,1,3)
plot(George_tbl.Time, George_tbl.CO)
ylabel('CO')
grid on

subplot(4,1,4)
plot(George_tbl.Time, George_tbl.TOL)
ylabel('TOL')
grid on
xlabel('Time [s]')