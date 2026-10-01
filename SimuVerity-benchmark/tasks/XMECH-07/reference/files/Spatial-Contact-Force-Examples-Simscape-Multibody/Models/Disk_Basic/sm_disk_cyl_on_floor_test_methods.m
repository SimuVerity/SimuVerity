mdl = 'sm_disk_cyl_on_floor';

open_system(mdl)

sm_disk_cyl_on_floor_enable_cyl('Solid')
sim(mdl)
cyl_wxSolid = simlog_sm_disk_cyl_on_floor.Bushing_Cyl_Solid.Rx.w.series;

sm_disk_cyl_on_floor_enable_cyl('Point Cloud')
sim(mdl)
cyl_wxPtcld = simlog_sm_disk_cyl_on_floor.Bushing_Cyl_Point_Cloud.Rx.w.series;

sm_disk_cyl_on_floor_enable_cyl('Disks')
sim(mdl)
cyl_wxDisks = simlog_sm_disk_cyl_on_floor.Bushing_Cyl_Disks.Rx.w.series;

sm_disk_cyl_on_floor_enable_cyl('All')

% Reuse figure if it exists, else create new figure
if ~exist('h1_sm_disk_cyl_on_floor', 'var') || ...
        ~isgraphics(h1_sm_disk_cyl_on_floor, 'figure')
    h1_sm_disk_cyl_on_floor = figure('Name', 'sm_disk_cyl_on_floor');
end
figure(h1_sm_disk_cyl_on_floor)
clf(h1_sm_disk_cyl_on_floor)

temp_colororder = get(gca,'defaultAxesColorOrder');

ah(1) = subplot(2,1,1);
plot(cyl_wxSolid.time,cyl_wxSolid.values,'LineWidth',1,...
    'DisplayName',['Solid: ' num2str(length(cyl_wxSolid.time)) ' steps']);
hold on
plot(cyl_wxPtcld.time,cyl_wxPtcld.values,'-','LineWidth',1,...
    'DisplayName',['Cloud: ' num2str(length(cyl_wxPtcld.time)) ' steps']);
plot(cyl_wxDisks.time,cyl_wxDisks.values,'--','LineWidth',1,...
    'DisplayName',['Disks: ' num2str(length(cyl_wxDisks.time)) ' steps']);
hold off
title('Comparing Contact Methods, Cylinder on Floor')
ylabel('w, Lateral Axis (rad/s)')
xlabel('Time (s)')
legend('Location','best')

ah(2) = subplot(2,1,2);
time_vec = cyl_wxSolid.time;
semilogy(time_vec(1:end-1),diff(cyl_wxSolid.time),'-','Marker','.','LineWidth',1);
hold on
time_vec = cyl_wxPtcld.time;
semilogy(time_vec(1:end-1),diff(cyl_wxPtcld.time),'LineWidth',1);
time_vec = cyl_wxDisks.time;
semilogy(time_vec(1:end-1),diff(cyl_wxDisks.time),'LineWidth',1);
hold off
title('Step Size During Simulation')
ylabel('Step Size (s)')
xlabel('Time (s)')
linkaxes(ah,'x')