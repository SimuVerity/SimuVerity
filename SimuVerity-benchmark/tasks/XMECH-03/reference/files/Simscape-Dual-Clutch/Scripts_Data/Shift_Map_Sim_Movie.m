function Shift_Map_Sim_Movie(dataset)
% USE MATLAB PLOTTING COMMANDS TO CREATE MOVIE OF LAST DCT SIMULATION
% Copyright 2011-2025 The MathWorks, Inc.

% GET DATA -- EITHER LAST SIMULATION RUN OR DATA FROM A STORED SIMULATION
if (strcmp(dataset,'lastrun'))
    vs_data1 = evalin('base','VehicleSpeed_DATA.signals.values');
    vs_time = evalin('base','VehicleSpeed_DATA.time');
    pd_data1 = evalin('base','Driver_DATA.signals(2).values');
    pd_time = evalin('base','Driver_DATA.time');
    er_data = evalin('base','Engine_DATA.signals(1).values');
    gr_data = evalin('base','CurrentGear_DATA.signals.values');
    gr_time = evalin('base','CurrentGear_DATA.time');
    vs_data = interp1(vs_time,vs_data1,gr_time,'linear');
    pd_data = interp1(pd_time,pd_data1,gr_time,'linear');
elseif (strcmp(dataset,'stored'))
    load DCTRES_Det_Ful_Des_Ori_DC7;
    evalin('base','Dual_Clutch_Trans_shiftmaporig');
    vs_data1 = DCTRES_Det_Ful_Des_Ori_DC7.VehicleSpeed.signals.values;
    vs_time = DCTRES_Det_Ful_Des_Ori_DC7.VehicleSpeed.time;
    pd_data1 = DCTRES_Det_Ful_Des_Ori_DC7.Driver.signals(2).values;
    pd_time = DCTRES_Det_Ful_Des_Ori_DC7.Driver.time;
    er_data = DCTRES_Det_Ful_Des_Ori_DC7.Engine.signals(1).values;
    gr_data = DCTRES_Det_Ful_Des_Ori_DC7.CurrentGear.signals.values;
    gr_time = DCTRES_Det_Ful_Des_Ori_DC7.CurrentGear.time;
    vs_data = interp1(vs_time,vs_data1,gr_time,'linear');
    pd_data = interp1(pd_time,pd_data1,gr_time,'linear');
end

% CONSTANTS
gearcolors = ['k' 'b','g','r','m','c'];
trace_length = 100;

% SET UP FIGURE
figure(3);
set(gcf,'Position',[456 62 560 619]);

% SET UP SHIFT MAP PLOT
subplot(211)
%set(gca,'Position',[0.13 0.43 0.775 0.2]);
pedal_pos = evalin('base','Pedal_Positions');
us_spd = evalin('base','Upshift_Speeds');
ds_spd = evalin('base','Downshift_Speeds');
Plot_Gear_Shift_Schedule(pedal_pos,us_spd,ds_spd);
legend({'1--2','2--3','3--4','4--5','5--6'},'Location','SouthEast')
hold on
tr_h = plot(vs_data(1:1+trace_length),pd_data(1:1+trace_length),'-','LineWidth',2);
hd_h = plot(vs_data(1+trace_length),pd_data(1+trace_length),'o',...
    'MarkerEdgeColor','k',...
    'MarkerSize',10,...
    'MarkerFaceColor','g');

% SET UP VEHICLE SPEED PLOT
subplot(212)
%set(gca,'Position',[0.13 0.11 0.775 0.2])
plot(gr_time,vs_data);
hold on
vspt_h = plot(gr_time(trace_length),vs_data(trace_length),'o',...
    'MarkerEdgeColor','k',...
    'MarkerSize',10,...
    'MarkerFaceColor','k');
xlabel('Time (s)','FontSize',12,'FontWeight','bold');
ylabel('Spd (kph)','FontSize',12,'FontWeight','bold');

% LOOP THROUGH SIMULATION DATA AND UPDATE PLOT DATA USING set COMMAND
for i=1:10:(length(vs_data)-trace_length)
    try
        set(tr_h,'XData',vs_data(i:i+trace_length),'YData',pd_data(i:i+trace_length));
        set(hd_h,'XData',vs_data(i+trace_length),'YData',pd_data(i+trace_length),'MarkerFaceColor',gearcolors(max(floor(gr_data(i+trace_length)),1)));
        set(vspt_h,'XData',gr_time(i+trace_length),'YData',vs_data(i+trace_length),'MarkerFaceColor',gearcolors(max(floor(gr_data(i+trace_length)),1)));
        pause(0.01);
    catch
    end
end
subplot(211);hold off
subplot(212);hold off
