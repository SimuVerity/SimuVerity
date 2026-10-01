# Simulink Documentation
Followed the Simulink Model in the Dissertacao PDF file. 
The model was implemented with the fixed step solver option with a step size of .01 seconds. Said model simulates a two wheel rear wheel drive formula car to attempt to build a representation of expected parameter values within a torque vectoring system. Matlab Simulink was used to build this representation. This system takes a steering value and the torque at both rear wheels as input, and calculates expected values for longitudinal and lateral velocity and acceleration, yaw rate, and desired yaw rate. 

This simulation can be run by selecting an appropriate stop time, selecting the log events option in Simulink, and clicking run. Logged data can be viewed by clicking data inspector within the review results box. Steering angle and torque input can be changed by modifying the value of the corresponding constant block connected to the input port of the subsystem. 

### Created blocks for each calculation step:
- Steering Kinematics
Using Ackerman geometry, transform steering angle to left and right wheel steering angle.

- Wheel Dynamics
Given right and left torque and rolling resistance, calculate angular velocity of wheels. 

- Slip Ratios
Given wheel angular velocities, side slip angles, and wheel velocities, calculate the ratio between the speed of the vehicle and the speed of it's wheels, or slip ratio. 

- Tire Model Burkhardt
Given the slip ratios of the wheels, calculate wheel friction using the Burkhardt model. 

- Vertical Loads
Given wheel friction and acceleration, calculate longitudinal and lateral force at wheels. 

- Wheel to Vehicle Coordinate System
Given longitudinal and Lateral forces at wheels, transform to get forces on the body of the car. 

- Rolling Force
Given forces at wheels and wheel angular velocities, calculate rolling force on wheels. 

- Force/Torque Equilibrium
Combine forces at wheels to calculate longitudinal and lateral acceleration, as well as yaw moment. 

- Side Slip Angle
Given longitudinal and lateral velocity of car and yaw rate, calculate side slip angle and wheel velocities. 
