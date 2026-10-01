clc; clear all; close all

A=[      0         0    1.0000         0
         0         0         0    1.0000
         0         0   -9.2751         0
         0         0         0   -3.4955];
     
B=[      0         0
         0         0
    2.3667    0.0790
    0.2410    0.7913];
C=[  1     0     0     0
     0     1     0     0];

 D=[  0     0
     0     0];

n=4;
w_n=8;
syms s
%%%%%%%%%%%%%%%%%%%%%% Butterworth Configuration %%%%%%%%%%%%%%%%%%%
Delta_c=zeros(n,n);
j=1;
poles=zeros(2*n,1);
left_poles=zeros(n,1);

% The roots are achived by:
poles=vpa(solve((s/w_n)^(2*n)==(-1)^(n+1)));

% consider poles in the left side of the Imaginary axes

for i=1:8
if real(poles(i,1))<0 ;
left_poles(j)=poles(i,1);
j=j+1;
end
end

% Characteristic Equation
N=poly(left_poles);
poles_2=left_poles;
for m=1:n+1
if m~=n+1
Delta_c= Delta_c + N(m)*A^(n-m+1);
else
Delta_c=Delta_c + N(m)*eye(n);
end
end


K_Butter = place(A,B,poles_2)  % K obtained from Butterworth criteria
A_new = A-B*K_Butter ;
sys_new = ss(A_new,B,C,D)
step(sys_new)

%% Response to Initial
% x0=[2 0 3 0]
% hold on
% initial(sys_new,x0)
% 
% grid minor
% 

