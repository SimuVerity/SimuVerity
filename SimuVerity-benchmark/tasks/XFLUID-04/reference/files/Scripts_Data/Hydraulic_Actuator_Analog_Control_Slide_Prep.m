% Copyright 2012-2025 The MathWorks, Inc.

colordef black;

time = Hydraulic_Acutator_Analog_Control_DATA.time;
Commanded_Position_Data = Hydraulic_Acutator_Analog_Control_DATA.signals.values(:,1);
Cylinder_Position_Data = Hydraulic_Acutator_Analog_Control_DATA.signals.values(:,2);

figure(1);
clf;
 


%new_sb211_h = 400;
set(gcf,'Position',[765    92   449   336]);

%set(gca,'Position',[0.15 0.63/522*new_sb211_h 0.775 0.341163*522/new_sb211_h])
%POSITION_211 = [0.15 0.583837 0.775 0.341163*522/new_sb211_h];
%subplot(211)
pos_h = plot(time,Hydraulic_Acutator_Analog_Control_DATA.signals.values);
set(pos_h(1),'Color','r');
set(pos_h(2),'Color','g');
set(pos_h,'LineWidth',3);
%hold on
%rct2_h = plot(time,Required_Crank_Torque2_data,'m');
title_h = title('Rod Position (mm)');
xlabel_h = xlabel('Time (s)');
ylabel_h = ylabel('Position (mm)');
%set(spd_h,'color',[0 0.3 1]);
set(title_h,'FontSize',14);
%set(xlabel_h,'FontSize',12);
set(ylabel_h,'FontSize',12);
grid on
set(gca,'Box','on');
%legend('No Friction','Friction','Location','Best');
%legend('Rod','Piston','Location',[0.2128    0.4421    0.2691    0.1622]);
axis([time(1) time(end) 50 62]);

