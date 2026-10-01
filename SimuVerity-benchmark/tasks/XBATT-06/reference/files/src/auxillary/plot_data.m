clc
clear

% fn = 'constantJump_batter_1.txt';
fn = 'data/data_test1.mat';
load(fn);

plot(data.tc,data.vc,'k');
yyaxis left
ylabel('V')
ylim([40,53])
yyaxis right
plot(data.tc,data.ic,'r');
ylabel('A')
ylim([0,100])
ax = gca;
ax.YAxis(2).Color = 'r';
xlim([0,max(data.tc)])
legend('voltage','current')
title('Experimental Voltage and Current Measurements')
xlabel('seconds, s')
set(gca,'FontSize',14)

saveas(gcf,'images/voltageAndCurrent_exp.png')
