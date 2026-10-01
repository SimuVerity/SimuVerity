# Closed-Loop simulation

This script demonstrates how to perform a closed loop simulation by calling the Python Anesthesia Simulator in MATLAB.

You can download the `pid_ratio` function used in this example from [here](pid_ratio.m), and the overall simulation script from [here](closed_loop_simulation.m).

---

## 🧪 Environment Setup

Set the Python environment to be used by MATLAB.

```matlab
clear all
clear pid_ratio
close all
clc

% For Windows users
env = pyenv('Version', ...
    'your_path\your_environment\Scripts\python.exe');

% For Linux/macOS users
% env = pyenv('Version', ...
%    '<python-environment>/bin/python');
```

---

## 🧍 Instantiate a Patient Object

Import the Python module and create a patient object with the specified characteristics.

```matlab
simulator = py.importlib.import_module('python_anesthesia_simulator.simulator');

age = 18;                           
height = 170;                       
weight = 60;                        
sex = 0;                         
sampling_time = 0.1;                

George = simulator.Patient([age, height, weight, sex],...
    ts = sampling_time);
```

---

## 🛠️ Controller Setup

Define the PID parameters and saturation limits.

```matlab
PID_params = struct( ...
    'Kp',        0.0286, ...
    'Ti',        206.98, ...
    'Td',        29.83, ...
    'Ts',        sampling_time,...
    'N',         5,  ...
    'ratio',     2, ...
    'uref_p',    0, ...
    'uref_r',    0, ...
    'sat_pos_p', 6.67, ...
    'sat_neg_p', 0, ...
    'sat_pos_r', 16.67, ...
    'sat_neg_r', 0 ...
);

y_sp = 50; % Setpoint for BIS
```

---

## 🛠️  Simulation Setup

Initialize simulation time and vectors for results.

```matlab
T_simu = 1200;
N_simu = floor(T_simu/sampling_time); 
T_sim  = sampling_time:sampling_time:T_simu;   

BIS = zeros(1,N_simu);
uProp = zeros(1,N_simu);
uRem  = zeros(1,N_simu);📊

uProp_k = PID_params.uref_p;
uRem_k = PID_params.uref_r;
```

---

## ▶️ Run the Simulation

Simulate the closed-loop control process using the PID controller.

```matlab
simulation_tuple = George.one_step(u_propo=uProp_k,...
        u_remi=uRem_k,...
        noise = false);
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
```

---

## 📊 Plotting Results

Visualize BIS response and drug infusion rates.

```matlab
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
```

---

## Notes

- The `pid_ratio` function must be implemented and available in your MATLAB path.
- The Python package `python_anesthesia_simulator` must be installed and accessible to the Python environment configured via `pyenv`.
