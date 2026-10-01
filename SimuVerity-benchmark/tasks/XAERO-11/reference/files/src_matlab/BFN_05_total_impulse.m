n=1;

% dt = detumbl(n).time(2:end)-detumbl(n).time(1:end-1);
% M = detumbl(n).control_thr(1:end-1,:);
dt = out.time(2:end)-out.time(1:end-1);
M = out.control_thr(1:end-1,:);
tI = 0;
for i=2048:length(dt)
T = fcn(M(i,:)',Thr_dist,Thr_dir);
tI = tI + T*dt(i);
end
tI(:)
sum(tI)
%% mission duration
I = [0.8997e-3,1.9054e-3];
t = 6000-300;
It = 5000;
Mis_time = It./(I/t)/3600/24/365
%% fuctions
function T_by_thruster = fcn(M_req,Thr_dist,Thr_dir)
M0 = cross(Thr_dist,Thr_dir);
M1 = bsxfun(@times, M_req/2,ones(3,12)).*(M0~=0);
T = -1*bsxfun(@rdivide,cross(Thr_dist,M1),dot(Thr_dist,Thr_dist)).*Thr_dir;
T = T.*(T>0);
T_by_thruster = sum(T,1);
end


