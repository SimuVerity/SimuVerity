%plot disturb torques
figure(4)
plot(out.dist_troques(:,1)/60,out.dist_troques(:,2:5))
legend('EMFT','RPT','ADT','GT')
grid on
grid minor
xlabel('Time, min')
ylabel('Torque, Nm')

