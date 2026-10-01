%sm_disk_floor_custom_friction_param

% Copyright 2022-2026 The MathWorks, Inc.

% Cylinder dimensions
cyl.rad  = 5;
cyl.len  = 1;
cyl.rho  = 1000;

% Contact parameters
cyl.solid.ck = 8e7;  % Contact stiffness
cyl.solid.cd = 4e6;  % Contact damping
cyl.solid.cw = 1e-2; % Contract transition width
cyl.solid.fs = 0.4;  % Static friction coefficient
cyl.solid.fd = 0.24;  % Dynamic friction coefficient
cyl.solid.fv = 1e-2; % Friction critical velocity

flr.len = 6*16;
flr.wid = 4*16;
flr.dep = 0.1*16;
flr.dim = [flr.len flr.wid flr.dep];

ice_start_px = 10;
ice.len = flr.len/2+1e-2-ice_start_px;
ice.wid = flr.wid+1e-2;
ice.dep = flr.dep;
ice.dim = [ice.len ice.wid ice.dep];

ice.offset = [flr.len/4+ice_start_px/2 0 1e-3];
