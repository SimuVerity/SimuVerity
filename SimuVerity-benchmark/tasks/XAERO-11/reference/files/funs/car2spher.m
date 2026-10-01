function sph_coords = car2spher(X)
%CAR2SPHER converts cartesian coordinates to spherical  
%   INPUT [X Y Z]
%   OUTPUT [Right accencion [rad], declination [rad], radius [as XYZ]]
RA = atan2(X(2),X(1));
if RA < 0
    RA = RA+2*pi;
end
r=sqrt(sum(X.^2));
decl = asin(X(3)/r);
sph_coords = [RA,decl,r];
end

