function [xP, vP] = ephMoon(MJD2000)

% ephMoon.m - Ephemerides (cartesian position and velocity) of the Moon.
% -------------------------------------------------------------------------

T_TDB = MJD2000/36525;

angles = [134.9 + 477198.85*T_TDB; ...    % L_ecl 1 and p 1
          259.2 - 413335.38*T_TDB; ...    % L_ecl 2 and p 2
          235.7 + 890534.23*T_TDB; ...    % L_ecl 3 and p 3
          269.9 +  954397.7*T_TDB; ...    % L_ecl 4 and p 4
          357.5 +  35999.05*T_TDB; ...    % L_ecl 5
          186.6 + 966404.05*T_TDB; ...    % L_ecl 6
           93.3 + 483202.03*T_TDB; ...    % phi_ecl 1
          228.2 + 960400.87*T_TDB; ...    % phi_ecl 2
          318.3 +   6003.18*T_TDB; ...    % phi_ecl 3
          217.6 -  407332.2*T_TDB; ...    % phi_ecl 4
          ];

% Transform angles in radians
angles = angles * pi/180;

% Sinus of the first 10 angles
s = sin(angles(1:10));

% Cosinus of the first 4 angles
c = cos(angles(1:4));


% Compute L_ecl, phi_ecl, P and eps
L_ecl =   (218.32 + 481267.883*T_TDB) ...
        + [+6.29, -1.27, +0.66, +0.21, -0.19, -0.11] * s(1:6);
    
phi_ecl = [+5.13, +0.28, -0.28, -0.17] * s(7:10);

P =   0.9508 ...
    + [+0.0518, +0.0095, +0.0078, +0.0028] * c;

eps = 23.439291 - 0.0130042*T_TDB - 1.64e-7*T_TDB^2 + 5.04e-7*T_TDB^3;

% Transform L_ecl, phi_ecl, P and eps in radians
L_ecl   = L_ecl   * pi/180;
phi_ecl = phi_ecl * pi/180;
P       = P       * pi/180;
eps     = eps     * pi/180;


r = 1/sin(P) * 6378.16; % Radius of the Earth copied from astro_constants for speed
% r = 1/sin(P) * 6371.01; % from Horizon (does not change much using one of
% the other...by Camilla
xP = r * [cos(L_ecl)*cos(phi_ecl), ...
    cos(eps)*cos(phi_ecl)*sin(L_ecl) - sin(eps)*sin(phi_ecl), ...
    sin(eps)*cos(phi_ecl)*sin(L_ecl) + cos(eps)*sin(phi_ecl)];

if nargout > 1
    vP = (ephMoon(MJD2000+1/86400) - xP);
end


return