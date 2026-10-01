function sm_four_bar_optim_plottraj(ref,orig,final,fig_h)
% Plot desired, initial, and final trajectories
% Copyright 2017-2025 MathWorks, Inc.

figure(fig_h)
if(~isempty(ref))
    ref = ref-min(ref);
    plot(ref(:,1),ref(:,2),'*','LineWidth',1,'Color',[0 0 0],'Marker','.','MarkerSize',8,'MarkerFaceColor',[0 0 0]);
    hold on
end

if(~isempty(orig))
    orig = orig-min(orig);
    plot(orig(:,1),orig(:,2),'r-','LineWidth',2);
    hold on
end

if(~isempty(final))
    final = final-min(final);
    plot(final(:,1),final(:,2),'b-','LineWidth',1);
end

% Set axes limits
sm_four_bar_optim_center_plot(gca,0.05);

grid on
axis equal
%{
XLims = get(gca,'XLim');
YLims = get(gca,'YLim');
[maxLowerLim,I] = max([XLims(1) YLims(1)]);

if (I==2)
    set(gca,'XLim',[maxLowerLim XLims(2)-abs(maxLowerLim)]);
else
    set(gca,'YLim',[maxLowerLim YLims(2)-abs(maxLowerLim)]);
end
%plot([0 0 maxXLim],[maxYLim 0 0],'Color',[1 1 1]*0.5,'LineWidth',3);
%}
hold off


