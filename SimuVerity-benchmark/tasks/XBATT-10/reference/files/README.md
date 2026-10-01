# EV_Truck_Model
A battery-electric truck model based on MATLAB/Simulink environment

_Shared by CJ. Peng, SOLAB, National Taiwan University_

For detailed vehicle parameters, procedure of development and model architecture, please refer to the thesis: 

*[Modeling of a modern electric truck with the integration of in-the-loop simulation technologies](https://tdr.lib.ntu.edu.tw/jspui/handle/123456789/88622)* _(DOI: 10.6342/NTU202302383)_

Please contact pengcj@solab.me.ntu.edu.tw for further discussion

## Basics about the electric truck model
### Simulation environment and necessary packages

MATLAB R2022b

Simulink with following package:
- Necessary Packages
	- Simscape
		- Electrical
		- Battery
	- Vehicle Dynamics Blockset
 		- Vehicle Body
  - Stateflow
- Optional Packages
	- Vehicle Network Toolbox
 		- CAN Communication

### What's in the package?
Two folders are provided in the root
- MATLAB Pre-defined Files: _This includes necessary files for simulation, choose one for simulation_
	- automation_NEDC.m: _Command for simulation under NEDC driving cycle_
  - automation_WLTP.m: _Command for simulation under WLTP driving cycle_
  - ***automation_REAL.m**: _Command for simulation under user pre-defined driving profile_ (default option for simulation)
  - User Defined Drive Cycle Profile: _User pre-defined driving profile, change if necessary_
  	- speed.mat: _Speed profile in MATLAB Data_
  	- time.mat: _Time profile in MATLAB Data_
- Simulink Vehicle Model
	- EV_Truck_Model.slx: _Simulink electric truck model to cooperate with MATLAB command, change if necessary_
	- Templete: _Pre-defined templetes for data inspector in Simulink_
		- TempleteNEDC.mldatx: _Templete for NEDC driving cycle_
    - TempleteWLTP.mldatx: _Templete for WLTP driving cycle_

## Simulation process
Users can select which driving profile to conduct for simulation, in the following context, examples of pre-defined driving profile and NEDC driving cycle are shown for selection. Simplified flowchart as following:
1. Open selected .m file in MATLAB
2. Set user defined parameters such as total mass, initial state of charge, powertrain...
3. Open vehicle model in Simulink
4. Select and set drvie cycle in _Drive Cycle and Visualization_ Block
5. Update simulation time
6. Check solver and step size in simulink in the bottom-right
7. Enable fast restart if multiple simulations are required to decrease the time for compiling
8. Run simulation in MATLAB
9. Select proper templete in Simulink data inspector
10. Save the results after end of simulation
### How to run simulation
#### What are parameters pre-defined
Users can change the following parameters in the .m files
If other parameters have to be changed, please go to Simulink model
	- Veh_mass: total vehicle mass in kg
	- Power_option: 3 powertrain options available
	- Batt_soc_init: initial state of charge of the vehicle, set between 0 to 100%
	- Elec_aux_sw: choose whether to activate auxiliary power components, which effects the driving mileage available
	- Elec_rgn_sw: choose whether to activate regenerative braking, users can re-define this function in _virtual VCU_
	- Run_number
#### User pre-defined driving profile
1. Open _automation_REAL.m_ in _MATLAB Pre-defined Files_ folder
2. Add both _MATLAB Pre-defined Files_ and _Simulink Vehicle Model_ to the path by selecting both folders in _Current Folder_ left hand side in MATLAB, select both folders and right click, choose _Add to Path_, _Selected Folders and Subfolders_ to ensure MATLAB can access files required during simulation
3. Run simulation by pressing Run button in EDITOR page, the process should proceed in few minutes
4. After the Simulink data inspector pops out, select proper templete in the page _Visualization and layouts_, _Saved views_, _Open saved views_
5. Save results after end of simulation
* Note: the whole process may take several hours according to the process ability of your hardware
#### For NEDC driving cycles
1. Open _automation_NEDC.m_ in _MATLAB Pre-defined Files_ folder
2. Add both _MATLAB Pre-defined Files_ and _Simulink Vehicle Model_ to the path by selecting both folders in _Current Folder_ left hand side in MATLAB, select both folders and right click, choose _Add to Path_, _Selected Folders and Subfolders_ to ensure MATLAB can access files required during simulation
3. Open Simulink model _EV_Truck_Model.slx_
4. Change the driving cycle by _Drive Cycle and Visualization_ block, reconnect the bus from user pre-defined profile to _Drive Cycle Source_
5. Open _Drive Cycle Source_, change _Drive Cycle Source_ to NEDC, _Update simulation time_ and save
6. Enable _Fast Restart_
7. Go back to MATLAB, Run simulation by pressing Run button in EDITOR page, the process should proceed in few minutes
8. After the Simulink data inspector pops out, select proper templete _TempleteNEDC.mldatx_ in the page _Visualization and layouts_, _Saved views_, _Open saved views_
9. Single simulation run may take a while according to the capability of your hardware, 48 cycles are conducted for single run, you may change to compositions in the loop of .m file
10. Save results after end of simulation

## Any problems?
Contact pengcj@solab.me.ntu.edu.tw for discussion

Copyright © 2023 CJ. Peng, SOLAB, NTU
