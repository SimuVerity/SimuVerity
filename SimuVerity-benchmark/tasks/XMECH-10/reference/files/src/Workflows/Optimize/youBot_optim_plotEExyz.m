% Copyright 2016-2025 The MathWorks, Inc.

%% Axes parameters

trajAxes.position = [0.0764    0.1100    0.6459    0.8150];
trajAxes.view = [-100 5];
trajAxes.axLim.X = [-0.4732    0.4058];
trajAxes.axLim.Y = [-0.3509    0.5280];
trajAxes.axLim.Z = [ 0         0.7641];

costAxes.position = [0.8061    0.1100    0.1329    0.8150];

[MinCost,MinIter] = min([EE_xyz_opt.cost]);

if (length(EE_xyz_opt)<200)
    SmallDotMarkerSize = 2;
else
    SmallDotMarkerSize = 1;
end

%% Figure 1: All Trajectories
if ~exist('h1_youbot_optim', 'var') || ...
        ~isgraphics(h1_youbot_optim, 'figure')
    h1_youbot_optim = figure('Name', 'h1_youbot_optim');
end
figure(h1_youbot_optim)
clf(h1_youbot_optim)

h_1=subplot(1,2,1);
hold on; grid on; box on
temp_colororder = get(gca,'defaultAxesColorOrder');
plot3(h_1,EE_xyz_opt(1).signals.values(1,1),...
    EE_xyz_opt(1).signals.values(1,2),...
    EE_xyz_opt(1).signals.values(1,3),'ks',...
    'MarkerFaceColor',temp_colororder(4,:),...
    'MarkerSize',8);
plot3(h_1,EE_xyz_opt(1).signals.values(end,1),...
    EE_xyz_opt(1).signals.values(end,2),...
    EE_xyz_opt(1).signals.values(end,3),'ks',...
    'MarkerFaceColor',temp_colororder(5,:),...
    'MarkerSize',8);

h_2=subplot(1,2,2);
hold on; grid on; box on

plot(h_2,1,EE_xyz_opt(1).cost/EE_xyz_opt(1).cost*100,'ks',...
    'MarkerFaceColor','b','MarkerSize',5,...
    'MarkerEdgeColor','b')

interval = 1;
for i=1:interval:length(EE_xyz_opt)
    if (EE_xyz_opt(i).cost<=EE_xyz_opt(1).cost)
        x = EE_xyz_opt(i).signals.values(:,1);
        y = EE_xyz_opt(i).signals.values(:,2);
        z = EE_xyz_opt(i).signals.values(:,3);
        plot3(h_1,x,y,z)        
        plot(h_2,i,EE_xyz_opt(i).cost/EE_xyz_opt(1).cost*100,'o',...
            'MarkerFaceColor',temp_colororder(1,:),'MarkerSize',SmallDotMarkerSize,...
            'MarkerEdgeColor',temp_colororder(1,:))
    end
end
set(h_1,'Position',trajAxes.position);
titleStrFriction = '(Low Friction)';
if strcmp(EE_xyz_opt_friction,'high')
    titleStrFriction = '(High Friction)';
end
title(h_1,['Trajectory of End Effector ' titleStrFriction]);
set(h_1,'XTickLabel',[],'YTickLabel',[],'ZTickLabel',[])
legend(h_1,{'Belt In','Belt Out'},'Location','NorthWest');

view(h_1,trajAxes.view(1),trajAxes.view(2));
set(h_1,'XLim',trajAxes.axLim.X,...
    'YLim',trajAxes.axLim.Y,...
    'ZLim',trajAxes.axLim.Z);
hold off

set(h_2,'Position',costAxes.position);
title(h_2,'Relative Cost (%)')
legend({'Manual'},'Location','east');
xlabel('Test #');
hold off

%% Figure 2: Original and Optimal Trajectories only
if ~exist('h2_youbot_optim', 'var') || ...
        ~isgraphics(h2_youbot_optim, 'figure')
    h2_youbot_optim = figure('Name', 'h2_youbot_optim');
end
figure(h2_youbot_optim)
clf(h2_youbot_optim)

h_1=subplot(1,2,1);
hold on; grid on; box on
h_2=subplot(1,2,2);
hold on; grid on; box on

set(h_1,'Position',trajAxes.position);
plot3(h_1,EE_xyz_opt(1).signals.values(1,1),...
    EE_xyz_opt(1).signals.values(1,2),...
    EE_xyz_opt(1).signals.values(1,3),'ks',...
    'MarkerFaceColor',temp_colororder(4,:),...
    'MarkerSize',8);
plot3(h_1,EE_xyz_opt(1).signals.values(end,1),...
    EE_xyz_opt(1).signals.values(end,2),...
    EE_xyz_opt(1).signals.values(end,3),'ks',...
    'MarkerFaceColor',temp_colororder(5,:),...
    'MarkerSize',8);
plot3(h_1,EE_xyz_opt(1).signals.values(:,1),...
    EE_xyz_opt(1).signals.values(:,2),...
    EE_xyz_opt(1).signals.values(:,3),...
    'LineWidth',2);
plot3(h_1,EE_xyz_opt(MinIter).signals.values(:,1),...
    EE_xyz_opt(MinIter).signals.values(:,2),...
    EE_xyz_opt(MinIter).signals.values(:,3),...
    'LineWidth',2);
title(h_1,['Trajectory of End Effector ' titleStrFriction]);
set(h_1,'XTickLabel',[],'YTickLabel',[],'ZTickLabel',[])
legend(h_1,{'Belt In','Belt Out','Manual','Optimal'},'Location','NorthWest');
view(h_1,trajAxes.view(1),trajAxes.view(2));
set(h_1,'XLim',trajAxes.axLim.X,...
    'YLim',trajAxes.axLim.Y,...
    'ZLim',trajAxes.axLim.Z);

% Plot cost for original and optimal
bar(h_2,1,EE_xyz_opt(1).cost/EE_xyz_opt(1).cost*100,'FaceColor',temp_colororder(1,:));
hold on
bar(h_2,2, EE_xyz_opt(MinIter).cost/EE_xyz_opt(1).cost*100,'FaceColor',temp_colororder(2,:));
hold off
set(gca,'XLim',[0 3]);
set(gca,'XTick',([0:1:3]));
set(gca,'XTickLabel','')
set(h_2,'Position',costAxes.position);
legend(h_2,{'Manual','Optimal'},'Location','Best');
title(h_2,'Relative Cost (%)')
hold off

%% Figure 3
if ~exist('h3_youbot_optim', 'var') || ...
        ~isgraphics(h3_youbot_optim, 'figure')
    h3_youbot_optim = figure('Name', 'h3_youbot_optim');
end
figure(h3_youbot_optim)
clf(h3_youbot_optim)

h_1=subplot(1,2,1);
hold on; grid on; box on
temp_colororder = get(gca,'defaultAxesColorOrder');

plot3(h_1,EE_xyz_opt(1).signals.values(1,1),...
    EE_xyz_opt(1).signals.values(1,2),...
    EE_xyz_opt(1).signals.values(1,3),'ks',...
    'MarkerFaceColor',temp_colororder(4,:),...
    'MarkerSize',8);
plot3(h_1,EE_xyz_opt(1).signals.values(end,1),...
    EE_xyz_opt(1).signals.values(end,2),...
    EE_xyz_opt(1).signals.values(end,3),'ks',...
    'MarkerFaceColor',temp_colororder(5,:),...
    'MarkerSize',8);

h_2=subplot(1,2,2);
hold on; grid on; box on

plot(h_2,1,EE_xyz_opt(1).cost/EE_xyz_opt(1).cost*100,'ks',...
    'MarkerFaceColor','b','MarkerSize',5,...
    'MarkerEdgeColor','b')

num_colors = 100;
cset = [...
    linspace(temp_colororder(2,1),temp_colororder(1,1),num_colors);...
    linspace(temp_colororder(2,2),temp_colororder(1,2),num_colors);...
    linspace(temp_colororder(2,3),temp_colororder(1,3),num_colors)]';

for i=1:interval:length(EE_xyz_opt)
    if (EE_xyz_opt(i).cost<=EE_xyz_opt(1).cost)
        x = EE_xyz_opt(i).signals.values(:,1);
        y = EE_xyz_opt(i).signals.values(:,2);
        z = EE_xyz_opt(i).signals.values(:,3);
        
        costColor = max(round(((EE_xyz_opt(i).cost-EE_xyz_opt(MinIter).cost)/(EE_xyz_opt(1).cost-EE_xyz_opt(MinIter).cost)*100),0),1);
        
        plot3(h_1,x,y,z,'-','Color',cset(costColor,:));        
        
        plot(h_2,i,EE_xyz_opt(i).cost/EE_xyz_opt(1).cost*100,'o',...
            'MarkerFaceColor',cset(costColor,:),'MarkerSize',SmallDotMarkerSize,...
            'MarkerEdgeColor',cset(costColor,:))
    end
end
set(h_1,'Position',trajAxes.position);
title(h_1,['Trajectory of End Effector ' titleStrFriction]);
set(h_1,'XTickLabel',[],'YTickLabel',[],'ZTickLabel',[])
legend(h_1,{'Belt In','Belt Out'},'Location','NorthWest');

view(h_1,trajAxes.view(1),trajAxes.view(2));
set(h_1,'XLim',trajAxes.axLim.X,...
    'YLim',trajAxes.axLim.Y,...
    'ZLim',trajAxes.axLim.Z);
hold off

set(h_2,'Position',costAxes.position);
title(h_2,'Relative Cost (%)')
legend({'Manual'},'Location','east');
xlabel('Test #');
hold off
