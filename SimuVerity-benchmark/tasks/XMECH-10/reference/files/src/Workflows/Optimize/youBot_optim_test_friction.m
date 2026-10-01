% Copyright 2016-2025 The MathWorks, Inc.

% Clear variable for storing results by function evaluation
clear EE_xyz_opt

% Run optimization
tic
[t, QOpt, Q0] = youBot_optim('youBot_Arm', YBT_Par,...
    YBT_Par.Waypoints.In2Out.Manual.t,...
    YBT_Par.Waypoints.In2Out.Manual.q(1:4,:));
toc

youBot_optim_plotEExyz

