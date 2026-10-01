function B = rot(axis,ang)
%Returns a rotation matrix around a specific axis
%   INPUT axis - x,y or z
%         angle in radians
switch axis
    case 'x'
        B = [1 0 0; 0 cos(ang) -sin(ang);0 sin(ang) cos(ang)];
    case 'y'
        B = [cos(ang) 0 sin(ang);0 1 0;-sin(ang) 0 cos(ang)];
    case 'z'
        B = [cos(ang) -sin(ang) 0; sin(ang) cos(ang) 0; 0 0 1];
    otherwise
        error('Bad axis in rotation matrix')
end

