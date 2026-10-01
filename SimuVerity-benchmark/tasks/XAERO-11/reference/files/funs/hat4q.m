function B = hat4q(q)
% calc hat4 quaternion used for attitude error calculation
if length(q)~=4
    error('Wrong dimensions at hat4q')
end
B =    [q(4) q(3) -q(2) -q(1);...
        -q(3) q(4) q(1) -q(2);...
        q(2) -q(1) q(4) -q(3);...
        q(1) q(2) q(3) q(4)];
end

