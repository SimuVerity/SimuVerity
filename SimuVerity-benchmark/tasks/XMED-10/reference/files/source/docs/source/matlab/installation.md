# Getting Started

This guide is intended for MATLAB users who want to exploit the features of the **Python Anesthesia Simulator**.  
It explains how to set up your environment, instantiate a `Patient` object from MATLAB, and connect it to **Simulink**.

---

## Prerequisites

* **MATLAB** R2024b or later  
* **Simulink** toolbox  
* **Python** 3.12 (recommended: use a virtual environment)  
* The **Python Anesthesia Simulator** package installed (`pip install .` inside the cloned repository)

---

## Configure the Python Environment

### Create a virtual environment (recommended)

```bash
python -m venv your_environment
```

### Activate the environment

**Windows**

```bash
your_environment\Scripts\activate
```

**macOS / Linux**

```bash
source your_environment/bin/activate
```

### Install the simulator package

```bash
pip install .
```

---

## Set Python Interpreter in MATLAB

Tell MATLAB to use your virtual environment’s Python interpreter:

```matlab
% Windows example
pyenv('Version', 'C:\path\to\your_environment\Scripts\python.exe');

% macOS/Linux example
% pyenv('Version', '<python-environment>/bin/python');
```

---

## Basic MATLAB Usage Example

```matlab
% Import the simulator module
simulator = py.importlib.import_module('python_anesthesia_simulator.simulator');

% Define patient parameters
age = 18; height = 170; weight = 60; sex = 0; % 0=female, 1=male
sampling_time = 1;

% Create a Patient object
George = simulator.Patient([age, height, weight, sex], ts=sampling_time);

```

Once instantiated, you can call methods on the Python `Patient` object directly from MATLAB.

---

## Using the Simulator in Simulink

Simulink can directly interact with Python objects through MATLAB wrapper functions.  
This section shows how to integrate the simulator for real-time co-simulation.

---

### Step 1 – Create `callPython.m`

Save this function in your MATLAB path:

```matlab
function [bis, co, map, tol, nmb] = callPython(u_p,u_r,u_n,u_a,age,height,weight,sex,sampling_time)
% callPython  Interface between Simulink and the Python Anesthesia Simulator.
%
%   [bis, co, map, tol, nmb] = callPython(u_p,u_r,u_n,u_a,age,height,weight,sex,sampling_time)
%   performs one simulation step of the Python patient model.
%
%   Inputs:
%       u_p  - Propofol infusion rate [mg/s]
%       u_r  - Remifentanil infusion rate [µg/s]
%       u_n  - Noradrenaline infusion rate [µg/s]
%       u_a  - Atracurium infusion rate [mg/s]
%       age, height, weight, sex - patient parameters
%       sampling_time - simulation sampling period [s]
%
%   Outputs:
%       bis - Bispectral Index
%       co  - Cardiac Output
%       map - Mean Arterial Pressure
%       tol - Tolerance to laryngoscopy
%       nmb - Neuromuscular Blockade level
%
%   Notes:
%       - Requires a configured Python environment via pyenv.
%       - Works only in Simulink **Normal** mode (not Accelerator or codegen).

    persistent simulator George

    % Initialize Python environment and patient once
    if isempty(simulator)
        simulator = py.importlib.import_module('python_anesthesia_simulator.simulator');
        George = simulator.Patient([age, height, weight, sex], ts=sampling_time);
    end

    % Run one simulation step
    simulation_tuple = George.one_step( ...
        u_propo=u_p, ...
        u_remi=u_r, ...
        u_nore=u_n, ...
        u_atra=u_a);

    % Convert Python outputs to MATLAB doubles
    simulation_cell = cell(simulation_tuple);
    bis = double(simulation_cell{1});
    co  = double(simulation_cell{2});
    map = double(simulation_cell{3});
    tol = double(simulation_cell{4});
    nmb = double(simulation_cell{5});
end
```

---

### Step 2 – Create `PythonStep.m` (Simulink wrapper)

This function is called from within your **Simulink MATLAB Function block**.

```matlab
function [bis, co, map, tol, nmb] = PythonStep(u_p,u_r,u_n,u_a,age,height,weight,sex,sampling_time)
% PythonStep  Simulink-compatible wrapper for Python anesthesia simulator
%
% This function acts as a bridge between Simulink and the Python patient model.
% It calls the `callPython` function at each simulation step.
%
% The outputs correspond to patient physiological variables:
% BIS, cardiac output, mean arterial pressure, tolerance to laryngoscopy, and NMB.

    coder.extrinsic('callPython')

    % Default values for Simulink codegen compatibility
    bis = 0; 
    co = 0;
    map = 0;
    tol = 0;
    nmb = 0;

    % Call Python through the MATLAB wrapper
    [bis, co, map, tol, nmb] = callPython(u_p,u_r,u_n,u_a,age,height,weight,sex,sampling_time);
end
```

---

### Step 3 – Configure Simulink

1. Add a **MATLAB Function Block** to your Simulink model.  
2. Replace its code with the content of `PythonStep.m`.  
3. Add the Inputs and Outputs:  
   * Inputs: `u_p`, `u_r`, `u_n`, `u_a`, `age`, `height`, `weight`, `sex`, `sampling_time`  
   * Outputs: `bis`, `co`, `map`, `tol`, `nmb`
4. Connect your infusion control signals and monitoring scopes as needed.  
5. Open **Simulation Settings → Solver**:
   * **Simulation mode:** `Normal`
   * **Fixed-step size:** equal to your `sampling_time`
6. Ensure `pyenv` is correctly configured before running the model.

---

### Step 4 – Resetting the Python Environment

To clear the persistent simulator and reload the Python module:

```matlab
clear callPython
```

This ensures that the `Patient` object is reinitialized on the next simulation.
