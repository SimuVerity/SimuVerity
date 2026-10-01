% Script for testing cost functions
% Copyright 2017-2025 MathWorks, Inc.

% Fixed Parameters
c = 0.2;  % m
d = 0.25; % m
h = 0.2;  % m

% Tuned Parameters
% Tune the lengths of the crank and connecting link
a_orig = 0.18; % m
b_orig = 0.25; % m

a_des = 0.12;
b_des = 0.27;

mdl = 'sm_four_bar_optim';
open_system('sm_four_bar_optim');

a=a_orig;b=b_orig;
simOut_orig=sim(mdl);
simOut_xy_pos = simOut_orig.logsout_sm_four_bar_optim.get('xy_pos');
xy_pos_orig = simOut_xy_pos.Values.Data;

a=a_des;b=b_des;
simOut_des=sim(mdl);
simOut_xy_pos = simOut_des.logsout_sm_four_bar_optim.get('xy_pos');
xy_pos_des = simOut_xy_pos.Values.Data;

c=c_des;d=d_des;
%save sm_four_bar_optim_des_new a_des b_des c_des d_des xy_pos_des xy_pos_orig

F= costFcnAreaPerimeter(xy_pos_des,xy_pos_orig);

function AreaPerimeterCost = costFcnAreaPerimeter(ref, test)
% Compute sum of difference between enclosed area and perimeter
area_ref = xyDatatoArea(ref);
area_test = xyDatatoArea(test);

perimeter_ref = xyDatatoPerimeter(ref);
perimeter_test = xyDatatoPerimeter(test);

AreaPerimeterCost = (area_ref-area_test)^2+(perimeter_ref-perimeter_test)^2;
% For debugging
disp(num2str([area_ref area_test perimeter_ref perimeter_test AreaPerimeterCost]));
end

function area = xyDatatoArea(xy_poly)
% Compute area of a planar polygon specified by an N x 2 matrix.

area = sum(sum(xy_poly .* ([1 -1] .* circshift(xy_poly, [-1 1])))) / 2;

end

function perimeter = xyDatatoPerimeter(xy_poly)
% Compute the perimeter of a planar polygon
% specified by an N x 2 matrix

seg_vectors = circshift(xy_poly, -1) - xy_poly; % Vectors along each polygon segment
perimeter = sum(sqrt(sum(seg_vectors .* seg_vectors, 2)));  % Sum of segment lengths
end
