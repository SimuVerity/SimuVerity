%% ========================================================================
%  Simulation of Python Anesthesia Simulator Patient Model in Simulink
%
%  This script configures MATLAB to use a custom Python environment,
%  runs a Simulink model that interfaces with a Python Anesthesia 
%  Simulator, and plots the simulation results.
%
%  ========================================================================

%% 1. Workspace Initialization
clear all          % Remove all variables, globals, functions, and MEX links
close all          % Close all open figure windows
clc                % Clear command window

%% 2. Configure Python Environment
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


%% 3. Define Simulation Parameters
simulation_time = 3600;   % Total simulation time in seconds (1 hour)

% Define patient parameters for the Python Patient class
age    = 18;      % Age in years
height = 170;     % Height in cm
weight = 60;      % Weight in kg
sex = 0;       % sex (0 = female, 1 = male)

sampling_time = 1;   % Simulation sampling time [s]

% Controller parameters
Kp = 0.0286;             % Proportional gain
Ti = 206.98;             % Integral time
Td = 29.83;              % Derivative time
Ts = 5;                  % Sampling time
N = 5;                   % Derivative filter parameter
ratio = 2;               % Remifentanil / Propofol ratio
uref_p = 0;              % Baseline infusion rate for Propofol
uref_r = 0;              % Baseline infusion rate for Remifentanil
sat_pos_p = 6.67;        % Max Propofol rate [mg/s]
sat_neg_p = 0;           % Min Propofol rate
sat_pos_r = 16.67;       % Max Remifentanil rate [ug/s]
sat_neg_r = 0;           % Min Remifentanil rate

%% 4. Run Simulink Model
% The Simulink model 'test_pythonPatient.slx' must contain a MATLAB Function
% block that calls the 'callPython' function to interface with Python.
%
% The simulation output structure 'y' should contain:
%   - y.bis   : Bispectral index (BIS) signal
%   - y.u_prop: Propofol infusion rate
%   - y.u_remi: Remifentanil infusion rate
%
% Make sure the model is set to 'Normal' simulation mode.
y = sim('sim_closedloop.slx');

%% 5. Plot Simulation Results

% --- BIS (Depth of Anesthesia)
subplot(3,1,1)
plot(y.bis, 'k', 'LineWidth', 1.2)
title('BIS')
hold on
grid on
ylabel('BIS')
xlabel('Time [s]')

% --- Propofol Infusion Rate
subplot(3,1,2)
plot(y.u_prop, 'k', 'LineWidth', 1.2)
title('Propofol Infusion Rate')
hold on
grid on
xlabel('Time [s]')
ylabel('Infusion Rate [mg/s]')

% --- Remifentanil Infusion Rate
subplot(3,1,3)
plot(y.u_remi, 'k', 'LineWidth', 1.2)
title('Remifentanil Infusion Rate')
hold on
grid on
xlabel('Time [s]')
ylabel('Infusion Rate [µg/s]')

%% 6. Clear Persistent Python Objects
% The function 'callPython' uses persistent variables to store the
% Python simulator object between simulation steps.
% Clearing the function removes those variables from memory.
clear callPython