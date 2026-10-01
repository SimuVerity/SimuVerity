%plot graphs of Torque and thrust profiles
%after running BFN_00_main.m and BFN_02_Thrusters.slx
figure(2)
subplot(2,1,1)
hold on
plot(out.thrusters_torque(:,1),out.thrusters_torque(:,2),'r-')
plot(out.thrusters_torque(:,1),out.thrusters_torque(:,3),'g-')
plot(out.thrusters_torque(:,1),out.thrusters_torque(:,4),'b-')
ylim([-2*Tmin*2.2*0.17 2*Tmin*2.2*0.17])
grid on
grid minor
xlabel('Time,s')
ylabel('Torque, Nm')
title('Torque produced by thrusters')
yticks(linspace(-6e-6,6e-6,11))
legend('Mx','My','Mz')

subplot(2,1,2)
hold on
plot(out.thrusters_torque(:,1),-out.thrusters_torque(:,5),'r-')
plot(out.thrusters_torque(:,1),-out.thrusters_torque(:,6),'g-')
plot(out.thrusters_torque(:,1),-out.thrusters_torque(:,7),'b-')
ylim([-1 9])
grid on
grid minor
xlabel('Time,s')
ylabel('Angular momentum error, %')
title('Angular momentum relative error')
legend('Mx','My','Mz')

figure(3)
subplot(2,1,1)
hold on
plot(out.thrusters_torque(:,1),out.thrusters_sequence)
legend('¹1,7','¹2,8','¹3,9','¹4,10','¹5,11','¹6,12')
grid on
grid minor
xlabel('Time,s')
ylabel('Thrust, N')
title('Thrust provided by each thruster')

subplot(2,1,2)
hold on
plot(out.thrusters_torque(:,1),out.thrusters_sequence)
legend('¹1,7','¹2,8','¹3,9','¹4,10','¹5,11','¹6,12')
grid on
grid minor
ylim([0 2.1e-5])
xlabel('Time,s')
ylabel('Thrust, N')
title('Thrust provided by each thruster refined')