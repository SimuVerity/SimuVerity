function E = kep_eq_E(M,e)
%KEP_EQ_E solves Kepler's equation by Newton E-e*sin(E)-M=0
%   INPUT M - mean anomaly in radians
%         e - eccentricity
%   OUTPUT E - eccentric anomaly in radians
tolerance = 1e-8;
E = M;
dE=10;
while abs(dE) > tolerance
    dE = (E-e*sin(E)-M)/(1-e*cos(E));
    E = E-dE;
end
end