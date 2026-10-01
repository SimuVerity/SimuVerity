function y = saturation(u,lim)
%Describes a saturation discontinuity
%   u - value
%   lim - saturation limit

y = (abs(u)<lim).*u + (abs(u)>=lim).*sign(u)*lim;

end

