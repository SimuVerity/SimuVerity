function c = powerFast(a,b)

c = a;
for i = 2:b
    c = c .* a;
end

end