## Simulation
This is a Python-based vehicle dynamics simulation tool that predicts the performance of a vehicle based on various 
physical parameters and driver inputs. The simulation helps in understanding the impact of these parameters on the 
vehicle's dynamics and control. The results are visualized in graph format for easy interpretation.

### How to Run by Command Line
1. There are multiple ways of running it. Either through an IDE or command-line. I'll be showing you through command-line.
2. First open a command prompt. Install python3 by typing python3, or by getting it from here: https://www.python.org/
3. After that, install a dependency called matplotlib. You can do that by typing: pip install matplotlib
4. Then, make sure you are in the correct directory for the simulation.py file. You can check by using the 'dir' command.
5. If not in the correct directory, then use 'cd <directory>' to get where you need to go. Use 'cd..' to go back one directory.
6. Lastly, once in the correct directory, run 'python3 <filename>' to run the simulation.
  
### Changing Parameters
There is a function near the bottom of the file named: "if __name__ == '__main__':"
Inside that function will be a 'simulate' function with arguments.
You can change these as you wish. It will be formatted like so:
simulate(<car velocity (m/s)>, <wheel velocity (m/s)>, <rear left wheel torque (Nm)>, <rear right wheel torque (Nm)>, <steering angle> (degrees))

### Features
1. Calculation of vehicle's yaw rate, yaw moment, lateral velocity, and desired yaw rate based on various physical 
parameters and driver inputs.
2. Simulation of the vehicle's dynamics based on steering angle, torque applied to each wheel, and velocities.
3. Uses the magic formula from Pacejka's tire model for calculating lateral force based on wheel slippage.
4. Includes a function to convert steering wheel angle to steering angle.
5. Generation of Look-Up-Table (LUT) for throttle and steering inputs based on the simulation results for efficient 
real-time performance.
6. Visualization of vehicle's performance parameters over time using Matplotlib.
7. Set of unit tests ensuring the correctness of the implemented functions.

### Terms Used
- Yaw Rate: Angular speed around vertical axis of the vehicle in rad/s.
- Longitudinal Velocity: Velocity along the length of the vehicle (Vx) in m/s.
- Cornering stiffness at rear wheel (Cy_r) and front wheel (Cy_f) in N/rad.
- Inertia Moment around z axis (Izz) in Kg/m^2.
- Mass of the vehicle (m) in Kg.
- Front wheelbase (lf) and rear wheelbase (lr) in m.
- Steering Angle (St_a) in degrees (converts from radians to degrees internally).
- Yaw Moment (M_V) in Nm.
- Yaw Moment around vertical axis (Mz).
- Lateral Velocity (Vy) in m/s.
- Gear Ratio (Gr) dimensionless.
- Half the track of the car (Tr) in m.
- Radius of the wheel (Rw) in m.

### Look-Up-Table Generation
The simulation comes with a file named make_lut.py. Simply running it will create a file that has a table that you can input into the microcontroller.
The x-axis will represent velocity from 0-80mph and the y-axis will represent steering angle converted from the steering wheel angle from 230 to
-230 degrees. The table resolution is controlled by the variables `steering_angle_resolution` and `velocity_resolution`. make_lut.py is multithreaded
by default, and outputs a visual indicator of the entries being generated. The table is output in C struct initializer format so that it can
be directly `#include`d into the C code.

### Unit Tests
In addition to the simulation functions, we have also provided a set of unit tests to validate the correctness of these 
functions. The unit tests are located in test_simulation.py. To run these tests, use the command pytest test_simulation.py.

### Dependencies
This simulator needs the following Python libraries:

math
random
array
numpy
matplotlib.pyplot
pytest (for testing the simulator)
