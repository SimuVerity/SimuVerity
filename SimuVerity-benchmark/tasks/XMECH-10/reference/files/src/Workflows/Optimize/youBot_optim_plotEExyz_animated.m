% Copyright 2016-2025 The MathWorks, Inc.

%% Axes parameters

trajAxes.position = [0.0764    0.1100    0.6459    0.8150];
trajAxes.view = [-100 5];
trajAxes.axLim.X = [-0.4732    0.4058];
trajAxes.axLim.Y = [-0.3509    0.5280];
trajAxes.axLim.Z = [ 0         0.7641];

costAxes.position = [0.8061    0.1100    0.1329    0.8150];

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

set(h_1,'Position',trajAxes.position);
titleStrFriction = '(Low Friction)';
if strcmp(EE_xyz_opt_friction,'high')
    titleStrFriction = '(High Friction)';
end
%title(h_1,['Trajectory of End Effector ' titleStrFriction]);
title(h_1,'Trajectory of End Effector','FontSize',16);
set(h_1,'XTickLabel',[],'YTickLabel',[],'ZTickLabel',[])
legend(h_1,{'Belt In','Belt Out'},'Location','NorthWest');

view(h_1,trajAxes.view(1),trajAxes.view(2));
set(h_1,'XLim',trajAxes.axLim.X,...
    'YLim',trajAxes.axLim.Y,...
    'ZLim',trajAxes.axLim.Z);

set(h_2,'Position',costAxes.position);
title(h_2,'Cost (%)','FontSize',16)
legend({'Manual'},'Location','east');
xlabel('Test #');
set(h_2,'XLim',[0 2000],...
    'YLim',[82 100]);

interval = 1;
pause(1)
for i=1:interval:length(EE_xyz_opt)
    if (EE_xyz_opt(i).cost<=EE_xyz_opt(1).cost)
        x = EE_xyz_opt(i).signals.values(:,1);
        y = EE_xyz_opt(i).signals.values(:,2);
        z = EE_xyz_opt(i).signals.values(:,3);
        plot3(h_1,x,y,z,'LineWidth',1)        
        plot(h_2,i,EE_xyz_opt(i).cost/EE_xyz_opt(1).cost*100,'o',...
            'MarkerFaceColor',temp_colororder(1,:),'MarkerSize',2,...
            'MarkerEdgeColor',temp_colororder(1,:))
    end
    pause(0.01)
end

