function Plot_Gear_Shift_Schedule(pedal_pos,upshift_spd,downshift_spd)
% CREATE PLOT OF SHIFT SCHEDULE
% Copyright 2011-2025 The MathWorks, Inc.

colors = ['b','g','r','m','c'];

for gear_i=1:size(upshift_spd,2)
    LineStyleStr = [colors(gear_i) '->'];
    plot([upshift_spd(1,gear_i); upshift_spd(:,gear_i); upshift_spd(end,gear_i)],[0 pedal_pos 1],LineStyleStr,'MarkerFaceColor',colors(gear_i));
    hold on
end
for gear_i=1:size(downshift_spd,2)
    LineStyleStr = [colors(gear_i) '--<'];
    plot([downshift_spd(1,gear_i); downshift_spd(:,gear_i); downshift_spd(end,gear_i);],[0 pedal_pos 1],LineStyleStr,'MarkerFaceColor',colors(gear_i));
    hold on
end

legend({'1--2','2--3','3--4','4--5','5--6'},'Location','Best')

axis([0 120 0 1])
grid on;
title('Gear Shifting Schedule','FontWeight','Bold','FontSize',14);
xlabel('Vehicle Speed (kph)','FontWeight','Bold','FontSize',12);
ylabel('Pedal Position (0-1)','FontWeight','Bold','FontSize',12);
hold off

    
