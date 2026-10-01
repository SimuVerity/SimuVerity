clc
clear

% fn = 'constantJump_batter_1.txt';
fn = 'constantJump_batter_1.txt';

temp = importdata(fn,',');
tm = temp(:,1);         % MATLAB time vector
tm_vec = datevec(tm);
s = tm_vec(:,4)*3600 + tm_vec(:,5)*60 + tm_vec(:,6);
t = temp(:,2)/1e-3;     % s, arduino time
V = temp(:,3);          % volts
I = temp(:,4);          % amps

plot(s,V,'k');
yyaxis right
plot(s,I,'r');
ax = gca;
ax.YAxis(2).Color = 'r';
