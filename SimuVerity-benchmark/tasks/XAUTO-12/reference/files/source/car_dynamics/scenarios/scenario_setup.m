%% Initialize Agent States
% Generate initial positions and velocities for agents distributed in a circle.
%   - config.R_circle: Radius of the circle.
%   - n_agents: Number of agents.
% Outputs:
%   - p_agents: Initial positions.
%   - v_agents: Initial velocities.
[p_agents, v_agents, theta_agents] = carsDistributedInCircle(config.R_circle, n_agents);

% Add random noise to positions based on the specified standard deviation.
p_agents = p_agents + config.p0_std * randn(size(p_agents));

% For a 2D environment, ensure the third coordinate is zero.
p_agents(3, :) = 0;

%% Define Agent Dimensions
dim_agents = ones(2, n_agents) * config.R_agent;

%% Set Agent Activity Flags
% Define whether each agent is passive (moves with constant velocity) or active 
% (uses control input). Here, all agents are set to active.
is_agent_passive = false(1, n_agents);

%% Initialize Sub-goals
% Create an empty cell array for sub-goals. In this scenario, sub-goals are not used.
sub_goals = cell(n_agents, 1);
