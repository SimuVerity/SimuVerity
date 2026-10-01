clc
clear

addpath auxillary\ data\ data_cut\ data_raw\

fn = 'data/data_test1.mat';
fn2 = 'data_cut/cdata_test1.mat';
load(fn)

ind = [1,9327,19705,29552,39976,50213,52975,58552];

ord = 7; framelen = 25; winlen = 10;
for i=1:length(ind)-1
    cdata(i).t = data.tc(ind(i):ind(i+1));
    cdata(i).v = data.vc(ind(i):ind(i+1));
    cdata(i).i = data.ic(ind(i):ind(i+1));
    cdata(i).r = data.rc(ind(i):ind(i+1));
    
    cdata(i).v = sgolayfilt(cdata(i).v,ord,framelen);
    cdata(i).i = sgolayfilt(cdata(i).i,ord,framelen);
    cdata(i).r = sgolayfilt(cdata(i).r,ord,framelen);

    cdata(i).v = movmean(cdata(i).v,winlen);
    cdata(i).i = movmean(cdata(i).i,winlen);
    cdata(i).r = movmean(cdata(i).r,winlen);

end
%%
save(fn2,'cdata')

%%
% k = 3;
% plot(data.tc,data.vc,'LineWidth',2)
% hold on
% plot(cdata(k).t,cdata(k).v,'r--','LineWidth',2)
% hold off
  
% axis([180,300,48,52])
