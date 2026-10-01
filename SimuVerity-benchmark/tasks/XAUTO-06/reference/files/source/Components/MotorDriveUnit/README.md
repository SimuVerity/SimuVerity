# Motor Drive Unit Component

This is a model of motor drive unit (MDU),
which is a system of electric motor and its controller.
The MDU model included in this component is highly abstract
and simulates the behavior of power conversion
between electric power and mechanical power
with the considerations for the power conversion efficiency.

The component is provided as a block in
Simulink library file

- `MotorDriveUnit_refsub_library.mdl`

It is designed to be used as a reusable model.
The content of the block is
`MotorDriveUnit_refsub_Basic.mdl`,
and its parameters are defined in
`MotorDriveUnit_refsub_Basic_params.m`.

`Harness` folder contains the following harness model
to run simulation with the Engine component.

- `MotorDriveUnit_Component_harness_model.mdl`

## Test Cases

`TestCases` folder contains Live Scripts
that are used to visually inspect the simulation behaviors
of the model in various simulation scenarios as follows.

- Constant ...
  All inputs are constant.
  This is used to check that the harness model runs.

- Start engine 1 ...
  Starting the engine with a motor is simulated.
  This first case is configured for a light mechanical load,
  with which engine can start without a reduction gear.

- Start engine 2 ...
  This is the same as the above case, but
  it is configured for a heavy mechanical load,
  similar to a passenger vehicle.
  A reduction gear is used to increase torque from engine.

_Copyright 2022 The MathWorks, Inc._
