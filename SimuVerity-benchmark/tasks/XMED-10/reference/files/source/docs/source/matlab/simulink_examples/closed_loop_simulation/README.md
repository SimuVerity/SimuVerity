# Closed-Loop Simulation in Simulink

This example demonstrates how to simulate a **closed-loop anesthesia control system** in **Simulink**, using the **Python Anesthesia Simulator** as the patient model.  
The files associated with this example can be downloaded by clicking on the following link:

- [main simulation file](main_sim_closedloop.m)
- [callPython function](callPython.m)
- [Simulink file](sim_closedloop.slx)

---

## Script Overview

File: **`main_sim_closedloop.m`**

The script performs the following steps:

1. **Initializes the workspace**
2. **Configures the Python environment** used by MATLAB
3. **Defines simulation and patient parameters**
4. **Specifies PID controller parameters and constraints**
5. **Runs the Simulink closed-loop model (`sim_closedloop.slx`)**
6. **Plots the simulation results**
7. **Clears Python persistent objects**

---

## 1. Workspace Initialization

```matlab
clear all
close all
clc
```

This ensures a clean workspace by removing all existing variables, closing figures, and clearing the command window.

---

## 2. Configure Python Environment

Specify the Python interpreter MATLAB will use. This must point to an environment containing the **Python Anesthesia Simulator** package.

**Windows Example:**
```matlab
env = pyenv('Version', ...
    '<python-environment>\Scripts\python.exe');
```

**macOS/Linux Example:**
```matlab
env = pyenv('Version', ...
    '<python-environment>/bin/python');
```

> ⚠️ Make sure the selected environment has the simulator installed via:
> ```bash
> pip install .
> ```

---

## 3. Define Simulation and Patient Parameters

```matlab
simulation_time = 3600;   % 1 hour

age    = 18;      % years
height = 170;     % cm
weight = 60;      % kg
sex = 0;       % 0 = female, 1 = male
sampling_time = 1;   % seconds
```

These are passed to the Python `Patient` class through the MATLAB-Python interface.

---

## 4. Define Controller Parameters

A standard **PID controller** regulates the drug infusion based on the BIS (Bispectral Index) feedback.

```matlab
Kp = 0.0286;             % Proportional gain
Ti = 206.98;             % Integral time
Td = 29.83;              % Derivative time
Ts = 5;                  % Sampling time
N = 5;                   % Derivative filter parameter
ratio = 2;               % Remifentanil / Propofol ratio
uref_p = 0;              % Baseline Propofol rate
uref_r = 0;              % Baseline Remifentanil rate
sat_pos_p = 6.67;        % Max Propofol rate [mg/s]
sat_neg_p = 0;           % Min Propofol rate
sat_pos_r = 16.67;       % Max Remifentanil rate [µg/s]
sat_neg_r = 0;           % Min Remifentanil rate
```

These parameters are used by the Simulink controller to compute drug infusion rates.

---

## 5. Run the Simulink Model

```matlab
y = sim('sim_closedloop.slx');
```

The Simulink model **`sim_closedloop.slx`** includes a MATLAB Function Block that calls the `callPython` function to communicate with Python.

### Required Files

| File | Description |
|------|--------------|
| **`callPython.m`** | Interfaces with the Python simulator and manages a persistent patient object |
| **`PythonStep.m`** | Simulink-compatible wrapper for `callPython.m` |
| **`sim_closedloop.slx`** | The Simulink model implementing the controller and patient system |

> ✅ **Important:** Set the simulation mode to **Normal** (not Accelerator or Rapid Accelerator).  
> Python calls are **not supported** in compiled modes.

---

## 6. Plot Simulation Results

The script automatically generates three plots:

- **BIS (Depth of Anesthesia)**
- **Propofol infusion rate**
- **Remifentanil infusion rate**

```matlab
subplot(3,1,1)
plot(y.bis, 'k', 'LineWidth', 1.2)
title('BIS')

subplot(3,1,2)
plot(y.u_prop, 'k', 'LineWidth', 1.2)
title('Propofol Infusion Rate')

subplot(3,1,3)
plot(y.u_remi, 'k', 'LineWidth', 1.2)
title('Remifentanil Infusion Rate')
```

Each subplot visualizes a key signal in the control loop.

---

## 7. Clear Persistent Python Objects

After running the simulation, clear the Python simulator object from memory:

```matlab
clear callPython
```

This step resets any persistent variables in `callPython.m`, ensuring a clean reinitialization for the next run.

---

## Example Workflow

1. **Open MATLAB** and configure Python:
   ```matlab
   pyenv('Version', 'C:\path\to\env\Scripts\python.exe')
   ```
2. **Open the model** `sim_closedloop.slx` and ensure simulation mode = Normal.  
3. **Run the script:**
   ```matlab
   sim_closedloop
   ```
4. **Inspect** BIS and infusion rate plots.
5. **Reset** the Python simulator:
   ```matlab
   clear callPython
   ```

---

## Output Variables

| Variable | Description | Units |
|-----------|--------------|--------|
| `y.bis` | Bispectral Index (Depth of Anesthesia) | – |
| `y.u_prop` | Propofol infusion rate | mg/s |
| `y.u_remi` | Remifentanil infusion rate | µg/s |

---

## Notes

- Use only **Normal Simulation Mode**.  
- Verify the Python environment path before running.  
- `callPython.m` and `PythonStep.m` must be on MATLAB’s path.  
- Clear persistent objects between consecutive runs.  
