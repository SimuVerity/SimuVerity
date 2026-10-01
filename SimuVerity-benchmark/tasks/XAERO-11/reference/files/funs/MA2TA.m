function TA = MA2TA(M,e)
%MA2TA calcs true anomaly from mean anomaly
%   INPUT M - mean anomaly in radians
%         e - eccentricity
%   OUTPUT TA - eccentric anomaly in radians
E = kep_eq_E(M,e);
TA = 2*atan(tan(E/2)*sqrt((1-e)/(1+e))^-1);
if TA < 0
    TA = TA+2*pi;
end
end

