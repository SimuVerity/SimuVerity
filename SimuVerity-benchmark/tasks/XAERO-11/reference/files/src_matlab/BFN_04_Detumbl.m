load('detumbl.mat')
%% plot omegas + control
for i=1:3
    figure(4+i)
    subplot(2,1,1)
    hold on
    plot(detumbl(i).time,detumbl(i).omega(:,1),'r-')
    plot(detumbl(i).time,detumbl(i).omega(:,2),'g-')
    plot(detumbl(i).time,detumbl(i).omega(:,3),'b-')
    grid on
    grid minor
    legend('wx','wy','wz')
    xlabel('Time, s')
    ylabel('Angular velocity, rad/s')
    
    subplot(2,1,2)
    hold on
    plot(detumbl(i).time,detumbl(i).control(:,1),'r-')
    plot(detumbl(i).time,detumbl(i).control(:,2),'g-')
    plot(detumbl(i).time,detumbl(i).control(:,3),'b-')
    grid on
    grid minor
    legend('ux','uy','uz')
    xlabel('Time, s')
    ylabel('Control torque, Nm')
end
%% plot magn and thrust controls
for i=1:3
    figure(7+i)
    subplot(3,1,1)
    hold on
    plot(detumbl(i).time,detumbl(i).control_magn(:,1),'r-')
    plot(detumbl(i).time,detumbl(i).control_magn(:,2),'g-')
    plot(detumbl(i).time,detumbl(i).control_magn(:,3),'b-')
    grid on
    grid minor
    legend('ux','uy','uz')
    xlabel('Time, s')
    ylabel('Torque, Nm')
    title('Magnetorquer')
    subplot(3,1,3)
    hold on
    plot(detumbl(i).time,detumbl(i).control_thr(:,1),'r-')
    plot(detumbl(i).time,detumbl(i).control_thr(:,2),'g-')
    plot(detumbl(i).time,detumbl(i).control_thr(:,3),'b-')
    grid on
    grid minor
    legend('ux','uy','uz')
    xlabel('Time, s')
    ylabel('Torque, Nm')
    title('Thrusters')
    subplot(3,1,2)
    hold on
    plot(detumbl(i).time,detumbl(i).m(:,1),'r-')
    plot(detumbl(i).time,detumbl(i).m(:,2),'g-')
    plot(detumbl(i).time,detumbl(i).m(:,3),'b-')
    grid on
    grid minor
    legend('mx','my','mz')
    xlabel('Time, s')
    ylabel('Magnetic moment, Am2')
    title('Magnetorquer')
end
