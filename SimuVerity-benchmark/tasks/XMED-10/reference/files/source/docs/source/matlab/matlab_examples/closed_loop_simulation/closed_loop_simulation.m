clear all
clear pid_ratio
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
age = 18;                           % years
height = 170;                       % cm
weight = 60;                        % kg
sex = 0;                         % 0 = female, 1 = male
sampling_time = 0.1;          % seconds

% Creates a patient object with specified parameters
George = simulator.Patient([age, height, weight, sex],...
    ts = sampling_time);

%% Controller Setup
% Define PID and system parameters
PID_params = struct( ...
    'Kp',        0.0286, ...        % Proportional gain
    'Ti',        206.98,  ...       % Integral time
    'Td',        29.83,   ...       % Derivative time
    'Ts',        sampling_time,...  % Sampling time
    'N',         5,  ...            % Derivative filter parameter
    'ratio',     2, ...             % Remifentanil / Propofol ratio
    'uref_p',    0,   ...           % Baseline infusion rate for Propofol
    'uref_r',    0, ...             % Baseline infusion rate for Remifentanil
    'sat_pos_p', 6.67,   ...        % Max Propofol rate [mg/s]
    'sat_neg_p', 0,   ...           % Min Propofol rate
    'sat_pos_r', 16.67,   ...       % Max Remifentanil rate [ug/s]
    'sat_neg_r', 0    ...           % Min Remifentanil rate
);

% Setpoint for BIS
y_sp = 50;

%% Simulation Setup
% Defines the total simulation time and calculates the number of simulation
% steps according to the sapling time

% total simulation time in seconds
T_simu = 1200;

% total number of simulation steps
N_simu = floor(T_simu/sampling_time); 

% Simulation time steps
T_sim  = sampling_time:sampling_time:T_simu;   

% Preallocate simulation vectors
BIS = zeros(1,N_simu);
uProp = zeros(1,N_simu);
uRem  = zeros(1,N_simu);

% Initial controller outputs
uProp_k = PID_params.uref_p;
uRem_k = PID_params.uref_r;



%% Run the simulation

% Perform an initial simulation step to obtain BIS_k
simulation_tuple = George.one_step(u_propo=uProp_k,...
        u_remi=uRem_k);
simulation_cell = cell(simulation_tuple);
BIS_k = double(simulation_cell{1});

% Executes the simulation
for k=1:1:N_simu

    [uProp_k, uRem_k] = pid_ratio(BIS_k, y_sp, PID_params);

    simulation_tuple = George.one_step(u_propo=uProp_k,...
        u_remi=uRem_k);
    simulation_cell = cell(simulation_tuple);
    BIS_k = double(simulation_cell{1});

    BIS(k) = BIS_k;
    uProp(k) = uProp_k;
    uRem(k) = uRem_k;

end

%% Plotting results

% Plotting
figure
subplot(3,1,1)
plot(T_sim, BIS, 'k', 'LineWidth', 1.5)
hold on
yline(y_sp, '--r')
title('Simulated BIS')
ylabel('BIS')
grid on

subplot(3,1,2)
plot(T_sim, uProp, 'b', 'LineWidth', 1.5)
title('Propofol Infusion')
ylabel('uProp [mg/s]')
grid on

subplot(3,1,3)
plot(T_sim, uRem, 'r', 'LineWidth', 1.5)
title('Remifentanil Infusion')
ylabel('uRem [ug/s]')
xlabel('Time [s]')
grid on
