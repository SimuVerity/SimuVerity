function X = spher2car(sph_coord)
%SPHER2CAR converts spherical coordinates to cartesian
%   INPUT [Right accencion [rad], declination [rad], radius [whatever]]
%   OUTPUT [X Y Z]
RA=sph_coord(:,1);decl=sph_coord(:,2);r=sph_coord(:,3);
X = r.*[cos(decl).*cos(RA) cos(decl).*sin(RA) sin(decl)]';
end

