% f = @(x,u) x;
% h = @(x,v,u) x + v;
% obj = unscentedKalmanFilter(f,h,52,'HasAdditiveMeasurementNoise',false);

n=2;      %number of state
q=0.01;    %std of process 
r=0.5;    %std of measurement
Q=q^2*eye(n); % covariance of process
R=r^2*eye(1);        % covariance of measurement  
%f=@(x)[x(2);x(3);0.05*x(1)*(x(2)+x(3))];  % nonlinear state equations
dv = [0;diff(voltage)]/10;
f=@(x,t)[x(1);dv(t)];
%h=@(x)x(1);                               % measurement equation
h=@(x,t) [voltage(t)];
% s=[0;0;1];                                % initial state
s = [voltage(1)];
x=s+q*randn(n,1); %initial state          % initial state with noise
P = eye(n);                               % initial state covraiance
N=2000;                                     % total dynamic steps
xV = zeros(n,N);          %estmate        % allocate memory
sV = zeros(n,N);          %actual
zV = zeros(1,N);
for k=1:N
  z = h(s,k);% + r*randn;                     % measurments
  sV(:,k)= s;                             % save actual state
  zV(k)  = z;                             % save measurment
  [x, P] = ukf(f,x,P,h,z,Q,R,k);            % ekf 
  xV(:,k) = x;                            % save estimate
  s = f(s,k) + q*randn(n,1);                % update process 
end
for k=1:n                               % plot results
  subplot(n,1,k)
  plot(1:N, sV(1,:), '-', 1:N, xV(1,:), '--')
  if k == 1
  hold on
  plot(1:N, voltage(1:N), 'g--')
  hold off
  end
end