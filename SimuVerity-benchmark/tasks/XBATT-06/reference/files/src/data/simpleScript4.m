clc
clear

lw = 200;

% -- import data
% load '2022-07-29 10-38-55_f1.mat'
% load '2022-08-04 10-58-30_f1.mat'
% load '2022-08-04 10-58-30_f2.mat'
% load '2022-08-08 10-44-35_f1.mat'
% load '2022-08-10 09-40-57_f1.mat'
% load '2022-09-26 11-49-08_f1.mat'
% load '2022-10-21 13-31-20_f1.mat'
fn = [{'2022-07-29 10-38-55_f1.mat'},
    {'2022-08-04 10-58-30_f1.mat'}
    {'2022-08-04 10-58-30_f2.mat'}
    {'2022-08-08 10-44-35_f1.mat'}
    {'2022-08-10 09-40-57_f1.mat'}
    {'2022-09-26 11-49-08_f1.mat'}
    {'2022-10-21 13-31-20_f1.mat'}];

for j=1:length(fn)
    Fn = char(fn(j));
    load(Fn)

    Cnom = 25;

    % -- compute landing approach cost & time
    k = find(r1<r2(1));
    r3 = r1(k);
    if ~isempty(r3)
        Cla(j) = I(r3(end)) - I(r3(1));
        dt_la(j) = t(r3(end)) - t(r3(1));
        Xla(j) = Cla(j)/Cnom;
    else
        Cla(j) = 0;
        dt_la(j) = 0;
        Xla(j) = 0;
    end

    % -- compute landing cost & time
    Cl(j) = I(r2(end)) - I(r2(1));
    dt_l(j) = t(r2(end)) - t(r2(1));
    Xl(j) = Cl(j)/Cnom;
end

dt = dt_l + dt_la;
X = Xl + Xla;
dt_l_mean = mean(dt_l);
Xl_mean = mean(Xl);
dt_la_mean = mean(dt_la(dt_la>0));
Xla_mean = mean(Xla(dt_la>0));
dt_mean = mean(dt);
X_mean = mean(X);

% -- analze results
figure(4)
clf
plot(dt,X,'b^','LineWidth',1.5); hold on
plot(mean(dt),mean(X),'bd','MarkerFaceColor','b')
plot(dt_l,Xl,'go','LineWidth',1.5)
plot(mean(dt_l),mean(Xl),'gd','MarkerFaceColor','g')
plot(dt_la(dt_la>=0),Xla(dt_la>=0),'rs','LineWidth',1.5)
plot(mean(dt_la(dt_la>0)),mean(Xla(dt_la>0)),'rd','MarkerFaceColor','r')
hold off
xlim([0,180])
grid on
title('SOC cost vs execution time')
xlabel('time, s'); ylabel('SOC cost')
legend('Combined', 'Avg. Combined',...
    'Landing','Avg. Landing',...
    'Approach','Avg. Approach',...
    'Location','southeast')
set(gca,'FontSize',14)

saveas(gcf,'landingcost','svg')
saveas(gcf,'landingcost','png')