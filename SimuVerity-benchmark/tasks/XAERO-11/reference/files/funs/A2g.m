function g = A2g(A)
%A2G DCN to gibbs vector
tmp = 1+A(1,1)+A(2,2)+A(3,3);
g = [(A(2,3)-A(3,2))/tmp;...
    (A(3,1)-A(1,3))/tmp;
    (A(1,2)-A(2,1))/tmp];
end

