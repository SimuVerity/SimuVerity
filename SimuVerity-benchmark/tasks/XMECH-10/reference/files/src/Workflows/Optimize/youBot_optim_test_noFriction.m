% Copyright 2016-2025 The MathWorks, Inc.

% optim
clear EE_xyz_opt

% Save current friction values
temp_fr = [...
    YBT_Par.Pivot.Motor.friction,...
    YBT_Par.Bicep.Motor.friction,...
    YBT_Par.Forearm.Motor.friction,...
    YBT_Par.Wrist.Motor.friction,...
    YBT_Par.Gripper.Motor.friction];

% Turn off friction
YBT_Par.Pivot.Motor.friction = 40*0;  % N*m/(rad/s)
YBT_Par.Bicep.Motor.friction = 40*0;  % N*m/(rad/s)
YBT_Par.Forearm.Motor.friction = 20*0;  % N*m/(rad/s)
YBT_Par.Wrist.Motor.friction = 8*0;  % N*m/(rad/s)
YBT_Par.Gripper.Motor.friction = 20*0;  % N*m/(rad/s)

% Run optimization
tic
[t, QOpt, Q0] = youBot_optim('youBot_Arm', YBT_Par,...
    YBT_Par.Waypoints.In2Out.Manual.t,...
    YBT_Par.Waypoints.In2Out.Manual.q(1:4,:));
toc

% Reset friction back to original values
YBT_Par.Pivot.Motor.friction = temp_fr(1);
YBT_Par.Bicep.Motor.friction = temp_fr(2);
YBT_Par.Forearm.Motor.friction = temp_fr(3);
YBT_Par.Wrist.Motor.friction = temp_fr(4);
YBT_Par.Gripper.Motor.friction = temp_fr(5);


