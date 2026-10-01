% Copyright 2011-2025 The MathWorks, Inc.

SweepData = whos('FuelUsedSweep2D*');
clear legendstrings
figure; 

for i = 1:length(SweepData);
    FU_SET = eval([SweepData(i).name '.FuelUsedSET']);
    rc_SET = eval([SweepData(i).name '.rampconst;']);
    mg_SET = eval([SweepData(i).name '.mingeardiff;']);
    varlabel1 = eval([SweepData(i).name '.Variants.Transmission']);
    varlabel2 = eval([SweepData(i).name '.Variants.SolverSettings']);
    
    %figure;
    set(gcf,'Position',[104   78   560   420]);
    set(gca,'CLim',[2 4.5]);
    [rc_array mgd_array] = meshgrid(rc_SET,mg_SET);
    %me_i(i) = mesh(mgd_array,rc_array,FU_SET(12:16,1:12));
    me_i(i) = mesh(mgd_array,rc_array,FU_SET,ones(size(FU_SET))*i*2);
    %surf(mgd_array,rc_array,FuelUsedSET);
    title('Fuel Use With Varying Shift Schedule','FontWeight','Bold','FontSize',14);
    xlabel('Offset Parameter','FontWeight','Bold','FontSize',12);
    ylabel('Ramp Parameter','FontWeight','Bold','FontSize',12);
    zlabel('Fuel Used (L)','FontWeight','Bold','FontSize',12);
    %legend('Parameter Sweep','Location','NorthWest');
    %text('Units','normalized','Position',[0.9 1 0],'String',varlabel1);
    %text('Units','normalized','Position',[0.9 0.95 0],'String',varlabel2);
    hold on;
    legstring = [varlabel1 ', ' varlabel2];
    legendstrings{i} = legstring;
end

hold off;
legend(legendstrings,'Location','Best');
set(gca,'ZLim',[0.16 0.19]);
