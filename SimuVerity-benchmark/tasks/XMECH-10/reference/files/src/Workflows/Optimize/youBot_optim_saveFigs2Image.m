% Copyright 2016-2025 The MathWorks, Inc.

figureList_h = [h1_youbot_optim h2_youbot_optim h3_youbot_optim];
figureList_n = {'allTrajectories' 'initialFinal' 'allTrajectories_clr'};

load youBot_optres_friction
youBot_optim_plotEExyz

for i=1:3
    fig = figureList_h(i);
    fig.InvertHardcopy = 'off';
    saveas(fig,['youBot_optim_res' '_Friction_' figureList_n{i} '.png'])
end

load youBot_optres_noFriction
youBot_optim_plotEExyz

for i=1:3
    fig = figureList_h(i);
    fig.InvertHardcopy = 'off';
    saveas(fig,['youBot_optim_res' '_noFriction_' figureList_n{i} '.png'])
end

youBot_optim_compare_trajectories

fig = h4_youbot_optim;
fig.InvertHardcopy = 'off';
saveas(fig,['youBot_optim_res' '_Compare_Trajectories' '.png'])
