%plot graphs of Gyro filtering
%after running BFN_00_main.m and BFN_01_Gyro_filter.slx
%% plot
figure(1)
subplot(3,1,1)
hold on
plot(gyro_filtr(:,1),gyro_filtr(:,2),'r-')
plot(gyro_filtr(:,1),gyro_filtr(:,3),'g-')
plot(gyro_filtr(:,1),gyro_filtr(:,4),'b-')
title('Real')
grid on
grid minor
xlabel('Time, s')
ylabel('omega, rad/s')
legend('wx','wy','wz')
subplot(3,1,2)
hold on
title('Gyro reading - Real')
plot(gyro_filtr(:,1),gyro_filtr(:,5)-gyro_filtr(:,2),'r-')
plot(gyro_filtr(:,1),gyro_filtr(:,6)-gyro_filtr(:,3),'g-')
plot(gyro_filtr(:,1),gyro_filtr(:,7)-gyro_filtr(:,4),'b-')
grid on
grid minor
ylim([-1 1]*1e-3)
xlabel('Time, s')
ylabel('omega, rad/s')
subplot(3,1,3)
hold on
plot(gyro_filtr(:,1),gyro_filtr(:,8)-gyro_filtr(:,2),'r-')
plot(gyro_filtr(:,1),gyro_filtr(:,9)-gyro_filtr(:,3),'g-')
plot(gyro_filtr(:,1),gyro_filtr(:,10)-gyro_filtr(:,4),'b-')
grid on
grid minor
xlabel('Time, s')
ylim([-1 1]*1e-4)
ylabel('omega, rad/s')
title('Filtered - Real')

R01.gyro = gyro_filtr(93000:end,5:10)-[gyro_filtr(93000:end,2:4) gyro_filtr(93000:end,2:4)];
R01.mean1 = mean(R01.gyro,1);
R01.var1 = var(R01.gyro,1);
R01.mean = [mean(R01.mean1(1:3)) mean(R01.mean1(4:6))];% mean in rad/s
R01.var = 100*[mean(R01.var1(1:3)) mean(R01.var1(4:6))]./R01.mean;% variance in %