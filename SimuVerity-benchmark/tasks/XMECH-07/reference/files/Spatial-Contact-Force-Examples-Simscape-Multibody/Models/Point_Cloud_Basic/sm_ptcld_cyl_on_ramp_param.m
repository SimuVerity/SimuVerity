function [cyl, ptcld] =  sm_ptcld_cyl_on_ramp_param(npts,showplot)
%sm_ptcld_cyl_on_ramp_param  Define parameters for sm_ptcld_cyl_on_ramp
%   [cyl, ptcld] =  sm_ptcld_cyl_on_ramp_param(npts)
%
%   You can specify:
%       npts      Estimated number of points about circumference
%                 of the cylinder. Points on cylinder ends will be in
%                 addition to this estimate, placed at the same points/area
%                 as on the cylinder circumference
%
% Copyright 2022-2026 The MathWorks, Inc.

% Cylinder dimensions
cyl.rad  = 5;
cyl.len  = 5;
cyl.rho  = 1000;
cyl.npts = npts;
cyl.area = (cyl.len*2*pi*cyl.rad)+2*(pi*cyl.rad^2);

% Contact parameters
cyl.solid.ck = 8e7;  % Contact stiffness
cyl.solid.cd = 4e6;  % Contact damping
cyl.solid.cw = 1e-4; % Contract transition width
cyl.solid.fs = 0.8;  % Static friction coefficient
cyl.solid.fd = 0.6;  % Dynamic friction coefficient
cyl.solid.fv = 1e-3; % Friction critical velocity

% Create point cloud
ptcld = Point_Cloud_Data_Cylinder(cyl.rad,cyl.len,cyl.npts,1,showplot);

% The stiffness and damping values depend upon the number of points that
% will penetrate the opposing surface. We scale those values based on the
% density (points/surface area) of the resulting point cloud
ptcld_size = size(ptcld,1);
ptsPerArea = ptcld_size/cyl.area;

cyl.ptcld.ck = cyl.solid.ck/10/ptsPerArea;
cyl.ptcld.cd = cyl.solid.cd/10/ptsPerArea*0.9;

% Use the same parameter values as the solid
cyl.ptcld.cw = cyl.solid.cw;
cyl.ptcld.fs = cyl.solid.fs;
cyl.ptcld.fd = cyl.solid.fd;
cyl.ptcld.fv = cyl.solid.fv;






