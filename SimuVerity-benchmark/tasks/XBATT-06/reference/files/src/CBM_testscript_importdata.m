clc
clear

addpath auxillary\ data\ data_cut\ data_raw\

fn = 'data/data_test1';
x = importdata('data_raw/constantJump_batter_1.txt',',');
t = datevec(x(:,1));
x = x(:,3:4);
t = 3600*t(:,4) + 60*t(:,5) + t(:,6);

x(t==0,:) = [];
t(t==0) = [];

t = t-t(1);
T = t(end)/3600;

plot(t,x(:,1),'k')
yyaxis right
plot(t,x(:,2),'r')

data.x = x; 
data.t = t;
data.T = T;

[C,IA,IC] =unique(data.t);
data.tc = C;
% data.tc = data.t(IC);
data.ic = data.x(IA,2);
data.vc = data.x(IA,1);
data.rc = data.vc./data.ic;
data.rc(isinf(data.rc)) = 1e2;
data.rc(isnan(data.rc)) = 1e2;

save([fn,'.mat'],'data')

writematrix([t,x],[fn,'.csv'])

cutData