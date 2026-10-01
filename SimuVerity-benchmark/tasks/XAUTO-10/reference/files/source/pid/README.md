# PID Controller

Authors: Ben Anderson & Matt Moradi

The PID controller simulation aims to simulate a closed loop feedback system within a vehicle torque vectoring system. It also serves as an accurate lookup table generator for use within the torque vectoring system. This is done using calculations from an established dissertation on formula-based torque vectoring systems. It simulates the adjustments of a PID controller used to change the power ratio between each wheel over time. The results of this simulation are then plotted onto a graph for analysis as well as exported to CSV for viewing in 3rd party applications. The characteristics and resolution of the simulation can be easily adjusted using the run arguments and the constants in the source code. Aside from the minor drawback of having to reconfigure the code to the characteristics of the vehicle model it's being applied to, we expect future use of this tool will help incorporate PID controllers into new cars and minimize real-time testing in theory.

## Compiling
1. Ensure cargo is installed on your system avaiable here: https://www.rust-lang.org/tools/install
2. `cd` to this `pid` directory
3. `cargo run <starting velocity (m/s)> <left wheel torque (Nm)> <right wheel torque (Nm)> <steering angle (degrees)>`

## Testing
Testing was performed on various vehicle characteristics using the plotters graphs for analysis. In addition to manual testing, unit testing was also preformed using the Rust language's built in testing framework. These tests are run automatically on every pull request and merge into the codebase. These tests can also be run using the command: `cargo test`
## Graphics
Yaw Rates | Velocities n' Slippage
:--:|:--:
![yawrates](https://github.com/VikingMotorsports/torque-vectoring/assets/14935352/8e0d3ae4-f378-471e-a5eb-6ad7d7a5592a) | ![velocities](https://github.com/VikingMotorsports/torque-vectoring/assets/14935352/0613666a-de14-40bf-bac3-8f539ab815fb)

## Recources
- [Dissertacao: Torque Vectoring for a Formula Student Prototype](https://fenix.tecnico.ulisboa.pt/downloadFile/563345090415567/Dissertacao.pdf)
- [Plotters Documentation](https://docs.rs/plotters/latest/plotters/)
- [CSV Writer Documentation](https://docs.rs/csv/latest/csv/struct.Writer.html)
- [Platform Directory Separator Docs](https://doc.rust-lang.org/std/path/constant.MAIN_SEPARATOR.html)
- [Directory Creation Docs](https://doc.rust-lang.org/std/fs/fn.create_dir_all.html)
- [Test Organization Docs](https://doc.rust-lang.org/book/ch11-03-test-organization.html)
- [VMS Python Simulation](https://github.com/VikingMotorsports/torque-vectoring/tree/main/simulation)

## License
This work is licensed under the "BSD-3 Clause". Please see the file `LICENSE.txt` in the root of this repo for license terms.
