# Vehicle1D Component

This is a model of longitudinal vehicle,
which computes the longitudinal speed of a road vehicle.

The main model file of this component is

- `Vehicle1D_refsub_Basic.mdl`

which is designed as a reusable component
as a referenced subsystem.
You can use it in a Subsystem Reference block.
The primary block of the main model is
[Longitudinal Vehicle block][url-1] from Simscape Driveline.

[url-1]:https://www.mathworks.com/help/physmod/sdl/ref/longitudinalvehicle.html

`Harness` folder contains the following harness model
to run simulation with the Vehicle1D component.

- `Vehicle1D_Component_harness_model.mdl`

## Test Cases

`TestCases` folder contains Live Scripts
that are used to visually inspect the simulation behaviors
of the model in various simulation scenarios as follows.

- Constant ...
  All inputs are constant.
  This is used to check that the harness model runs.

- Coastdown ...
  Simulation starts with a constant vehicle speed
  with no driving torque on the flat ground.
  Vehicle naturally comes to a complete stop.

- Brake ...
  Vehicle starts going down hill.
  Then brake is applied to slow down the vehicle speed.

*Copyright 2022 The MathWorks, Inc.*
