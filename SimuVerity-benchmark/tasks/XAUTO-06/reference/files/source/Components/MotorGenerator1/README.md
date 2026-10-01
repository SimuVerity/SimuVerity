# Motor Generator 1 Component

This is a model of motor drive unit
specifically parameterized for Motor Generator 1 (MG1),
which is used as part of power-split hybrid electric vehicle.
MG1 controls the power splitting of internal combustion engine
to distribute engine's mechanical power for
driving vehicle axle and generating electric power.
This component is designed to be used
as a reusable model.

The main block is in Simulink library file
`MotorGenerator1_refsub_library.mdl`.
Harness model `MotorGenerator1_Component_harness_model.mdl`
in the `Harness` folder is used to test the block.

This component depends on the Motor Drive Unit component.

## Test Cases

`TestCases` folder contains Live Scripts
that are used to visually inspect the simulation behaviors
of the model in various simulation scenarios as follows.

- Constant ...
  All inputs are constant.
  This is used to check that the harness model runs.

- Start engine ...
  MG1 starts engine.

- Generate ...
  MG1 converts engine's mechanical power
  to generate electric power.

- Stop engine ...
  Engine stops operating, and then
  MG1 tries to spin engine crank in the reverse direction
  which is prevented by sprag clutch.

_Copyright 2022 The MathWorks, Inc._
