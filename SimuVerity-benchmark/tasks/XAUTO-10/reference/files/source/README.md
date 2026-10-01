# Torque Vectoring

This repository hosts the codebase for torque vectoring development project for the VMS 3rd generation Formula EV. Torque vectoring pertains to the implementation of  an electronic differential, or e-diff, which is intended to reduce wheel slippage by outputting different power to each wheel’s motor based on information about the state of the vehicle along with the relevant formulas.

## Components
- Microcontroller - e-diff code for performing realtime torque vectoring calulations on the STM32F446RE board
- PID Controller - closed loop feedback sytem simulation for generating an accurate lookup table
- Simulation - python simulation of the torque vectoring calulations
- Simulink - model-based design simulation of the torque vectoring system

## Architecture
![TorqueVectoringArchitectureDiagram drawio (1)](https://github.com/VikingMotorsports/torque-vectoring/assets/14935352/490e3316-0397-48cb-8855-05df1020b395)
