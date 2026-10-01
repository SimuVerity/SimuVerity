% Copyright 2016-2025 The MathWorks, Inc.

modelname = 'youBot_Arm';
tests = {'Optim_Manual','Optim_Friction','Optim_NoFriction'};
for i = 1:length(tests)
    youBot_configureTest(modelname,tests{i});
    sim(modelname)
    costRes.(tests{i}).xyz = EE_xyz;
    costRes.(tests{i}).cost = logsout_youBot_Arm.get('electrical_cost');
end

%% Axes parameters

trajAxes.position = [0.0764    0.1100    0.6459    0.8150];
trajAxes.view = [-100 5];
trajAxes.axLim.X = [-0.4732    0.4058];
trajAxes.axLim.Y = [-0.3509    0.5280];
trajAxes.axLim.Z = [ 0         0.7641];

costAxes.position = [0.8061    0.1100    0.1329    0.8150];

%% Figure 4: Compare trajectories
if ~exist('h4_youbot_optim', 'var') || ...
        ~isgraphics(h4_youbot_optim, 'figure')
    h4_youbot_optim = figure('Name', 'h4_youbot_optim');
end
figure(h4_youbot_optim)
clf(h4_youbot_optim)

h_1=subplot(1,2,1);
hold on; grid on; box on

temp_colororder = get(gca,'defaultAxesColorOrder');

h_2=subplot(1,2,2);
hold on; grid on; box on

set(h_1,'Position',trajAxes.position);

for i = 1:length(tests)
    
    plot3(h_1,costRes.(tests{i}).xyz.signals.values(:,1),...
        costRes.(tests{i}).xyz.signals.values(:,2),...
        costRes.(tests{i}).xyz.signals.values(:,3),...
        'LineWidth',2);
end

plot3(h_1,costRes.(tests{1}).xyz.signals.values(1,1),...
    costRes.(tests{1}).xyz.signals.values(1,2),...
    costRes.(tests{1}).xyz.signals.values(1,3),'ks',...
    'MarkerFaceColor',temp_colororder(4,:),...
    'MarkerSize',8);
plot3(h_1,costRes.(tests{1}).xyz.signals.values(end,1),...
    costRes.(tests{1}).xyz.signals.values(end,2),...
    costRes.(tests{1}).xyz.signals.values(end,3),'ks',...
    'MarkerFaceColor',temp_colororder(5,:),...
    'MarkerSize',8);
title(h_1,'Trajectory of End Effector');
set(h_1,'XTickLabel',[],'YTickLabel',[],'ZTickLabel',[])
legend(h_1,{'Manual','Optim. for High Friction','Optim. for Low Friction'},'Location','NorthWest');
view(h_1,trajAxes.view(1),trajAxes.view(2));
set(h_1,'XLim',trajAxes.axLim.X,...
    'YLim',trajAxes.axLim.Y,...
    'ZLim',trajAxes.axLim.Z);

% Plot cost for original and optimal
maxcost = max([...
    costRes.(tests{1}).cost.Values.Data;...
    costRes.(tests{2}).cost.Values.Data;...
    costRes.(tests{3}).cost.Values.Data]);
for i=1:length(tests)
    bar(h_2,i,costRes.(tests{i}).cost.Values.Data/maxcost*100,'FaceColor',temp_colororder(i,:));
    hold on
end
hold off
set(gca,'XLim',[0 4]);
set(gca,'XTick',([0:1:4]));
set(gca,'XTickLabel','')
set(h_2,'Position',costAxes.position);
title(h_2,'Relative Cost (%)')
text(-0.05,60,sprintf('%s\n%s','Test conducted','with high friction'),...
    'BackGroundColor','white',...
    'EdgeColor','black')

