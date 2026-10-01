function B = B_calc(vb,vn,a)
%B_CALC calcs B matrix for SVD, q and QUEST methods
a = a/norm(a);
B = zeros(3);
for i=1:length(a)
    B = B + a(i)*vb(:,i)*vn(:,i)';
end
end

