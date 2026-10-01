# Motor Generator 2 Component

This is a model of motor drive unit
specifically parameterized for Motor Generator 2 (MG),
which is used as part of power-split hybrid electric vehicle.
MG2 is the primary driving motor of a vehicle.
It is also used for regenerative braking.

This component is designed to be used
as a reusable model.

The main block is in Simulink library file
`MotorGenerator2_refsub_library.mdl`.
Harness model `MotorGenerator2_Component_harness_model.mdl`
in the `Harness` folder is used to test the block.

This component depends on the Motor Drive Unit component.

## Test Cases

`TestCases` folder contains Live Scripts
that are used to visually inspect the simulation behaviors
of the model in various simulation scenarios as follows.

- Constant ...
  All inputs are constant.
  This is used to check that the harness model runs.

- Drive ...
  MG2 drives vehicle.

- Regen ...
  MG2 converts vehicle's mechanical power
  to generate electric power.
  This simulates regenerative braking.

_Copyright 2022 The MathWorks, Inc._
