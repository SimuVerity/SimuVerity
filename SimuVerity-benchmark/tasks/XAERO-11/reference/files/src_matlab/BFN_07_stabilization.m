t_set=2048;
%% Dynamics kinematics control
figure(14)
subplot(3,1,1)
hold on
plot(out.time(t_set:end)/60,out.omega(t_set:end,1),'r-')
plot(out.time(t_set:end)/60,out.omega(t_set:end,2),'g-')
plot(out.time(t_set:end)/60,out.omega(t_set:end,3),'b-')
grid on
grid minor
legend('wx','wy','wz')
xlabel('Time, s')
ylabel('Angular velocity, rad/s')
title('Angular velocity')
subplot(3,1,2)
hold on
plot(out.time(t_set:end)/60,out.control(t_set:end,1),'r-')
plot(out.time(t_set:end)/60,out.control(t_set:end,2),'g-')
plot(out.time(t_set:end)/60,out.control(t_set:end,3),'b-')
grid on
grid minor
legend('Mx','My','Mz')
xlabel('Time, s')
ylabel('Torque, Nm')
title('Total control torque')
ylim([-1 1]*2e-5)
subplot(3,1,3)
hold on
plot(out.time(t_set:end)/60,out.ang_e(t_set:end),'r-')
grid on
grid minor
xlabel('Time, s')
ylabel('Angle, deg')
title('Attitude error')
%ylim([-1 1]*180)
%% Control
figure(15)
subplot(3,1,1)
hold on
plot(out.time(t_set:end)/60,out.control(t_set:end,1),'r-')
plot(out.time(t_set:end)/60,out.control(t_set:end,2),'g-')
plot(out.time(t_set:end)/60,out.control(t_set:end,3),'b-')
grid on
grid minor
legend('Mx','My','Mz')
xlabel('Time, s')
ylabel('Torque, Nm')
title('Total control torque')
ylim([-1 1]*2e-5)
subplot(3,1,2)
hold on
plot(out.time(t_set:end)/60,out.control_magn(t_set:end,1),'r-')
plot(out.time(t_set:end)/60,out.control_magn(t_set:end,2),'g-')
plot(out.time(t_set:end)/60,out.control_magn(t_set:end,3),'b-')
grid on
grid minor
legend('Mx','My','Mz')
xlabel('Time, s')
ylabel('Torque, Nm')
title('Magnetorquer')
ylim([-1 1]*6e-7)
subplot(3,1,3)
hold on
plot(out.time(t_set:end)/60,out.control_thr(t_set:end,1),'r-')
plot(out.time(t_set:end)/60,out.control_thr(t_set:end,2),'g-')
plot(out.time(t_set:end)/60,out.control_thr(t_set:end,3),'b-')
grid on
grid minor
legend('Mx','My','Mz')
xlabel('Time, s')
ylabel('Torque, Nm')
title('Thrusters')
ylim([-1 1]*2e-5)

%% Att error
figure(16)
hold on
plot(out.time(t_set:end)/60,out.att_det_err(t_set:end,1),'r-')
plot(out.time(t_set:end)/60,out.att_det_err(t_set:end,2),'g-')
plot(out.time(t_set:end)/60,out.att_det_err(t_set:end,3),'b-')
plot(out.time(t_set:end)/60,out.att_det_err(t_set:end,4),'m-')
grid on
grid minor
legend('q1','q2','q3','q4')
xlabel('Time, s')
ylabel('Quaternion')
title('Attitude determination error')

mean1 = [mean(out.att_det_err(:,1)) mean(out.att_det_err(:,2)) mean(out.att_det_err(:,3)) mean(out.att_det_err(:,4))];
var1 = 100*[var(out.att_det_err(:,1)) var(out.att_det_err(:,2)) var(out.att_det_err(:,3)) var(out.att_det_err(:,4))]./mean1;
mean(mean1(1:3))
mean(var1(1:3))