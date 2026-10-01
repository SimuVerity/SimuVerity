# Open loop simulation

This script demonstrates how to perform an open loop simulation by calling the Python Anesthesia Simulator in MATLAB.
You can download the overall simulation script from [here](open_loop_simulation.m).

---

## 🧪 Environment Setup

To use Python functions inside MATLAB, configure the Python environment:

### For **Windows** users

Replace the path with your actual Python environment path:

```matlab
env = pyenv('Version', ...
    'your_path\your_environment\Scripts\python.exe');
```

### For **Linux/macOS** users

```matlab
% env = pyenv('Version', ...
%    '<python-environment>/bin/python');
```

---

## 🧍 Instantiate a Patient Object

Import the simulator module and create a patient with specified parameters:

```matlab
simulator = py.importlib.import_module('python_anesthesia_simulator.simulator');

% Define patient parameters
age = 18; height = 170; weight = 60; sex = 0; sampling_time = 1;

George = simulator.Patient([age, height, weight, sex], ts = sampling_time);
```

---

## 🛠️ Simulation Setup

Define total simulation time and drug infusion profiles:

```matlab
T_simu = 3600; % seconds
N_simu = floor(T_simu / sampling_time);

% Infusion profiles [zeros by default]
propofol_infusion_profile = zeros(N_simu, 1);
remifentanil_infusion_profile = zeros(N_simu, 1);

% Propofol profile
propofol_infusion_profile(1:floor(50/sampling_time)) = 2;
propofol_infusion_profile(floor(121/sampling_time):end) = 0.2;

% Remifentanil profile
remifentanil_infusion_profile(1:floor(30/sampling_time)) = 1;
remifentanil_infusion_profile(floor(121/sampling_time):end) = 0.1;
```

---

## ▶️ Run the Simulation

```matlab
df = George.full_sim(u_propo = propofol_infusion_profile,...
                     u_remi = remifentanil_infusion_profile);
George_tbl = table(df); % Convert Python DataFrame to MATLAB table
```

---

## 📊 Plotting Results

### Drug Concentrations and Infusion Rates

```matlab
figure
subplot(2,1,1)
plot(George_tbl.Time, George_tbl.x_propo_4, 'DisplayName', 'Propofol [ug/ml]')
hold on
plot(George_tbl.Time, George_tbl.x_remi_4, 'DisplayName', 'Remifentanil [ng/ml]')
xlabel('Time [s]'); 
ylabel('Effect Site Concentration');
legend('Location','southeast'); 
grid on
title('Effect site concentrations and infusion rates')

subplot(2,1,2)
plot(George_tbl.Time, George_tbl.u_propo, 'DisplayName', 'Propofol [mg/s]')
hold on
plot(George_tbl.Time, George_tbl.u_remi, 'DisplayName', 'Remifentanil [ug/s]')
ylabel('Infusion Rate'); legend('Location','northeast');
grid on
```

### Physiological Responses

```matlab
figure
subplot(4,1,1);
plot(George_tbl.Time, George_tbl.BIS);
ylabel('BIS');
grid on;
title('Physiological responses')

subplot(4,1,2);
plot(George_tbl.Time, George_tbl.MAP);
ylabel('MAP');
grid on

subplot(4,1,3);
plot(George_tbl.Time, George_tbl.CO);
ylabel('CO');
grid on

subplot(4,1,4);
plot(George_tbl.Time, George_tbl.TOL);
ylabel('TOL');
xlabel('Time [s]');
grid on
```