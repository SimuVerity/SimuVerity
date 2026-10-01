function [pAgents, vAgents, thetaAgents] = carsDistributedInCircle(Rcircle, nAgents)
% Agents are positioned in a circle, keeping the same angle separation
% between any two consecutives

deltaTheta = 2 * pi / nAgents;

pAgents = zeros([3, nAgents]);
vAgents = zeros([1 nAgents]);

thetaAgents = zeros([1 nAgents]);

for i = 0:(nAgents - 1)
    theta_i = deltaTheta * i;
    pAgents(:,i+1) = [cos(theta_i); sin(theta_i); 0] * Rcircle;
    thetaAgents(i+1) = atan2(-pAgents(2,i+1), -pAgents(1,i+1));
end

end