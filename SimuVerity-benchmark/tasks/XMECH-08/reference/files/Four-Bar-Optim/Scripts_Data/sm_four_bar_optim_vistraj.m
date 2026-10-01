function sm_four_bar_optim_vistraj(model,showhide)
% Shows or hides initial trajectory for optimization in sm_four_bar_optim
% Copyright 2017-2025 The MathWorks, Inc.

spl_h = find_system([model '/Length D'],'RegExp','on','IncludeCommented','on','LookUnderMasks','all','FollowLinks','on','Name','Visualize.*');

if(strcmpi(showhide,'show'))
    commented = 'off';
else
    commented = 'on';
end
for i=1:length(spl_h)
    set_param(spl_h{i},'Commented',commented);
end
