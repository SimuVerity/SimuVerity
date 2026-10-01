# Open-loop simulation in Simulink

This example demonstrates how to run the **Python Anesthesia Simulator** inside **Simulink** through MATLAB’s Python interface.
The files associated with this example can be downloaded by clicking on the following link:

- [main simulation file](main_sim_openloop.m)
- [callPython function](callPython.m)
- [Simulink file](sim_openloop.slx)

---

## Script Overview

File: **`main_sim_openloop.m`**

The script performs the following steps:

1. **Clears the MATLAB workspace**  
2. **Configures the Python environment** to use the simulator backend  
3. **Defines simulation and patient parameters**  
4. **Runs a Simulink model (`sim_openloop.slx`)**  
5. **Plots** the simulation outputs (BIS and drug infusion rates)  
6. **Clears the Python interface** to free memory

---

## 1. Workspace Initialization

```matlab
clear all
close all
clc
```

These commands reset the MATLAB session by removing all variables, closing figures, and clearing the console.

---

## 2. Configure Python Environment

Before running the simulation, specify which Python interpreter MATLAB should use.

```matlab
env = pyenv('Version', ...
    'your_path\your_environment\Scripts\python.exe');
```

Replace the path above with the location of your virtual environment’s `python.exe`.

**Example (Windows):**
```matlab
env = pyenv('Version', '<python-environment>\Scripts\python.exe');
```

**Example (macOS/Linux):**
```matlab
env = pyenv('Version', '<python-environment>/bin/python');
```

> ⚠️ The environment must have the **`python_anesthesia_simulator`** package installed (`pip install .`).

---

## 3. Define Simulation Parameters

```matlab
simulation_time = 3600;   % 1 hour

age    = 18;      % years
height = 170;     % cm
weight = 60;      % kg
sex = 0;       % 0 = female, 1 = male

sampling_time = 1;   % [s]
```

These parameters are passed to the Python simulator through the Simulink model.

---

## 4. Run Simulink Model

```matlab
y = sim('sim_openloop.slx');
```

The Simulink model `sim_openloop.slx` must contain:

- A **MATLAB Function Block** that calls the function:
  ```matlab
  [bis, co, map, tol, nmb] = PythonStep(u_p,u_r,u_n,u_a,age,height,weight,sex,sampling_time);
  ```
- The `PythonStep` block internally calls `callPython.m`, which manages communication with Python.

### Required Files
| File | Role |
|------|------|
| `callPython.m` | Creates and maintains a Python `Patient` object |
| `PythonStep.m` | Simulink wrapper for `callPython.m` |
| `sim_openloop.slx` | Simulink model running the simulation |

> ✅ **Simulation Mode must be set to “Normal”**  
> (Python calls are not supported in Accelerator or Code Generation modes.)

---

## 5. Plot Simulation Results

After running the model, the script visualizes:

- **BIS** (depth of anesthesia)
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

Each subplot corresponds to one of the patient’s key signals, plotted over the simulation time.

---

## 6. Clear Persistent Python Objects

At the end of the script:

```matlab
clear callPython
```

This command clears the persistent variables stored in `callPython.m`, which hold the Python `Patient` instance.  
It ensures that the next simulation starts with a fresh Python object.

---

## Example Workflow

1. Open MATLAB and ensure your Python environment is active:
   ```matlab
   pyenv('Version','C:\path\to\env\Scripts\python.exe')
   ```
2. Open and configure `sim_openloop.slx` (Normal mode).  
3. Run the simulation:
   ```matlab
   main_sim_openloop
   ```
4. Inspect the BIS and drug infusion plots.
5. Reset the Python interface when done:
   ```matlab
   clear callPython
   ```

---

## Output Signals

| Signal | Description | Units |
|---------|--------------|--------|
| `y.bis` | Bispectral Index (depth of hypnosis) | – |
| `y.u_prop` | Propofol infusion rate | mg/s |
| `y.u_remi` | Remifentanil infusion rate | µg/s |

---

## Notes

- Works only in **Normal Simulation Mode**.  
- `pyenv` must point to a valid Python environment containing the simulator.  
- Each run initializes or reuses a persistent Python `Patient` instance.  
- Use `clear callPython` between runs to fully reset the model.  
