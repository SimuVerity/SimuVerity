function B = hat4(w)
%HAT4 forms a 4hat matrix from vector used for kinemitics quaternion
%integration
%   3x1 vector as input
%   4x4 matrix as output
B =    [0 w(3) -w(2) w(1);...
        -w(3) 0 w(1) w(2);...
        w(2) -w(1) 0 w(3);...
        -w(1) -w(2) -w(3) 0];
end

