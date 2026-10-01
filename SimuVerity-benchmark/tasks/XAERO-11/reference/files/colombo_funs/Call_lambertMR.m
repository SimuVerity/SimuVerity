%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%                                                                         %
%                       ORBITAL MECHANICS                                 %
%                                                                         %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%
% DESCRIPTION: Sample script illustating the use of lambertMR


clc;
clear;


muSun = 132712e6;      % mu Sun [km^3/s^2];
ToF = 50*86400;                 % Time in [s];
[A,P,E,ERROR,VI,VF,TPAR,THETA] = lambertMR( [10000,0,0], [20000,0,0], ToF, muSun, 0, 0, 0 );