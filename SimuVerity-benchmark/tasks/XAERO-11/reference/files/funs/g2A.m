function A = g2A(g)
% g2A GIBBS vector to cosine matrix 
%   gibbs vector in input
% its a redneck way to do algorithm from week 4 lectures page 10
% 04/01/2020
if length(g)~=3
    error('Wrong Gibbs vector')
end
A = [1+g(1)^2-g(2)^2-g(3)^2 2*(g(1)*g(2)+g(3)) 2*(g(1)*g(3)-g(2));
    2*(g(1)*g(2)-g(3)) 1-g(1)^2+g(2)^2-g(3)^2 2*(g(2)*g(3)+g(1));
    2*(g(1)*g(3)+g(2)) 2*(g(2)*g(3)-g(1)) 1-g(1)^2-g(2)^2+g(3)^2]/...
    (1+g(1)^2+g(2)^2+g(3)^2);


end

