function B = hat3(a)
%HAT3 forms a 3hat matrix from vector for DCN kinematics integration
%   3x1 vector as input
%   3x3 matrix as output
B = [0 -a(3) a(2);a(3) 0 -a(1);-a(2) a(1) 0];
end

