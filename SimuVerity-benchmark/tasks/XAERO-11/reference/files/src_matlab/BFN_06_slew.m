%% Dynamics kinematics control
figure(11)
subplot(3,1,1)
hold on
plot(out.time,out.omega(:,1),'r-')
plot(out.time,out.omega(:,2),'g-')
plot(out.time,out.omega(:,3),'b-')
grid on
grid minor
legend('wx','wy','wz')
xlabel('Time, s')
ylabel('Angular velocity, rad/s')
title('Angular velocity')
subplot(3,1,2)
hold on
plot(out.time,out.control(:,1),'r-')
plot(out.time,out.control(:,2),'g-')
plot(out.time,out.control(:,3),'b-')
grid on
grid minor
legend('Mx','My','Mz')
xlabel('Time, s')
ylabel('Torque, Nm')
title('Total control torque')
ylim([-1 1]*1e-4)
subplot(3,1,3)
hold on
plot(out.time,out.qe(:,1),'r-')
plot(out.time,out.qe(:,2),'g-')
plot(out.time,out.qe(:,3),'b-')
plot(out.time,out.qe(:,4),'m-')
grid on
grid minor
legend('q1','q2','q3','q4')
xlabel('Time, s')
ylabel('Quaternion')
title('Attitude error')
%% Control
figure(12)
subplot(3,1,1)
hold on
plot(out.time,out.control(:,1),'r-')
plot(out.time,out.control(:,2),'g-')
plot(out.time,out.control(:,3),'b-')
grid on
grid minor
legend('Mx','My','Mz')
xlabel('Time, s')
ylabel('Torque, Nm')
title('Total control torque')
ylim([-1 1]*1e-4)
subplot(3,1,2)
hold on
plot(out.time,out.control_magn(:,1),'r-')
plot(out.time,out.control_magn(:,2),'g-')
plot(out.time,out.control_magn(:,3),'b-')
grid on
grid minor
legend('Mx','My','Mz')
xlabel('Time, s')
ylabel('Torque, Nm')
title('Magnetorquer')
ylim([-1 1]*5e-6)
subplot(3,1,3)
hold on
plot(out.time,out.control_thr(:,1),'r-')
plot(out.time,out.control_thr(:,2),'g-')
plot(out.time,out.control_thr(:,3),'b-')
grid on
grid minor
legend('Mx','My','Mz')
xlabel('Time, s')
ylabel('Torque, Nm')
title('Thrusters')
ylim([-1 1]*1e-4)

%% Att determ error
figure(13)
hold on
plot(out.time,out.att_det_err(:,1),'r-')
plot(out.time,out.att_det_err(:,2),'g-')
plot(out.time,out.att_det_err(:,3),'b-')
plot(out.time,out.att_det_err(:,4),'m-')
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