clc; clear all; close all

%% Add paths for required functions and configurations
addpath(genpath("setup_functions\"));
addpath(genpath("generated_functions\"));
addpath(genpath("scenarios\"));
addpath(genpath("tools\"));

%% Simulation Setup
modelName = "fourCars"; % select simulink model from "scenarios/"
n_agents = str_to_number(replace(modelName, "Cars", ""));

config_file = "sim_config"; 
setup_file = "scenario_setup.m";

%% Load Configuration and Initialize Agents
run(config_file); % Load simulation configuration
run(setup_file); % Load model-specific configuration

global agentsInfo;
agentsInfo = cell(1, n_agents); % Preallocate cell array for agent data

for i = 1:n_agents
    agent_t.p = p_agents(:, i);   % Initial position
    agent_t.v = v_agents(i);   % Initial velocity
    agent_t.theta = theta_agents(i);
    
    % Set goal position (opposite position if no sub-goal exists)
    if isempty(sub_goals{i})
        agent_t.p_goal = -agent_t.p;
    else
        agent_t.p_goal = sub_goals{i};
    end
    
    % Agent properties
    agent_t.dim = dim_agents(:, i);   % Dimensional properties
    agent_t.debug = true;            % Enable debugging information
    agent_t.passive = is_agent_passive(i); % Passive agent flag
    
    agentsInfo{i} = agent_t;
end

%% Run Simulation
base_path = dir(".").folder;
absModelPath = strcat(base_path, "/scenarios/", modelName, ".slx");
sim_out = sim(absModelPath);

%% Store Simulation Results
sim_out.config = config;
sim_out.n_agents = n_agents;
sim_out.p_agents = p_agents;
sim_out.v_agents = v_agents;
sim_out.theta_agents = theta_agents;
sim_out.dim_agents = dim_agents;
sim_out.is_agent_passive = is_agent_passive;

% Generate a unique filename for saving results
simulationFileName = sprintf("%s_%s_%d", modelName, config_file, int64(rand(1) * 1e12));

% Save simulation output to a .mat file
save(sprintf("out/%s.mat", simulationFileName), "sim_out", "-mat");

%% Handle Demo Video File
movieFile = "demo.avi";
movefile(movieFile, sprintf("demos/%s.avi", simulationFileName));

disp("Simulation completed successfully. Results saved in 'out/' directory.");