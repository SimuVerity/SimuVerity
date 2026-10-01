# Automotive Electrical System Simulation and Control

[![View Automotive Electrical System Simulation and Control on File Exchange](https://www.mathworks.com/matlabcentral/images/matlab-file-exchange.svg)](https://www.mathworks.com/matlabcentral/fileexchange/25674-automotive-electrical-system-simulation-and-control)
[![Open in MATLAB Online](https://www.mathworks.com/images/responsive/global/open-in-matlab-online.svg)](https://matlab.mathworks.com/open/github/v1?repo=mathworks/automotive-electrical-system&file=ssc_battery_management_R2019b.slx)

A conventional vehicle electrical system model with alternator, battery, loads, and idle control.

This model shows an example of a conventional vehicle electrical system model, which was shown in the webinar "Optimizing Vehicle Electrical Design through System-Level Simulation". The model is intended to study component sizing, selection, and control. 
 http://www.mathworks.com/videos/optimizing-vehicle-electrical-design-through-system-level-simulation-81919.html

The electrical system model contains a Simscape lead-acid battery model as described in SAE Paper 2007-01-0778. There are two choices for battery size. 
https://www.mathworks.com/content/dam/mathworks/tag-team/Objects/s/40542_SAE-2007-01-0778-Battery-Modeling-Process.pdf 

The model also contains data-driven alternator model options using either look-up tables or Model-Based Calibration Toolbox blocks. The alternator model is described in SAE Paper 2007-01-3471.

Control may be added to monitor the system condition, and increase idle speed to compensate for bad conditions in the vehicle charging system.
Vehicle loads are modeled as variable resistive elements.

Simulink Design Optimization can be used to estimate battery parameters from experimental battery data. To see how, please watch this video (5 min):
http://www.mathworks.com/videos/estimating-parameters-of-a-battery-68957.html

Parameter estimation for these models from measured data sets at different temperature and current data is a complex task. To learn how MathWorks Consulting can teach you this technique, please contact us or see:

MathWorks Consulting: Battery Simulation and Controls
http://www.mathworks.com/services/consulting/proven-solutions/battery-simulation-and-controls.html
