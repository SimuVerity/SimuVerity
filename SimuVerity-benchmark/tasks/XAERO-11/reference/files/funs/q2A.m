function A = q2A(q)
%q2A Quaternion to DCN
%   quaternion in input
% it's a redneck way to write: A=(q(4)^2-q'*q)*I+2*q*q'-2*q(4)*q^;
% 04/01/2020
if (length(q)~=4)||(abs(norm(q)-1)>0.1)
    error('Wrong quaternion input')
end
% A = [q(1)^2-q(2)^2-q(3)^2+q(4)^2 2*(q(1)*q(2)+q(3)*q(4)) 2*(q(1)*q(3)-q(2)*q(4));...
%     2*(q(1)*q(2)-q(3)*q(4)) -q(1)^2+q(2)^2-q(3)^2+q(4)^2 2*(q(2)*q(3)+q(1)*q(4));...
%     2*(q(1)*q(3)+q(2)*q(4)) 2*(q(2)*q(3)-q(1)*q(4)) -q(1)^2-q(2)^2+q(3)^2+q(4)^2];
A=(q(4)^2-q(1:3)'*q(1:3))*eye(3)+2*q(1:3)*(q(1:3)')-2*q(4)*hat3(q(1:3));

for i=1:5
    A = A*3/2-A*(A')*A/2;
end
end

