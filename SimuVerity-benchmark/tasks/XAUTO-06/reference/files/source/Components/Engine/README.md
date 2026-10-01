# Engine Component

This is a model of internal combustion engine
designed for use as part of power-split hybrid electric vehicle.
Engine is used for both driving axle and generating electric power.

This component is designed to be used
as a reusable model `Engine_refsub_Basic.mdl`.
Its parameters are defined in  `Engine_refsub_Basic_params.m`.

`Harness` folder contains a harness model
`Engine_Component_harness_model.mdl`
to run simulation with the Engine component.

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
  Starting the engine with a motor is simulated.
  This second case is configured for a heavy mechanical load,
  similar to a passenger vehicle.
  Engine parameteres are the same with the light load case.
  A reduction gear is used to increase engine torque.

_Copyright 2022 The MathWorks, Inc._
