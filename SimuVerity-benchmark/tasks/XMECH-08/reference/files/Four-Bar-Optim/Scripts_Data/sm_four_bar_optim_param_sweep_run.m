% Parameter sweep for four-bar linkage to see possible trajectories
% Copyright 2017-2025 MathWorks, Inc.

% Fixed lengths
c = 0.2;  % m
d = 0.25; % m
h = 0.2;  % m

% Set range for sweep of adjustable lengths
%
% Four-bar linkages can be grouped into various cases based on the lengths
% of their links.  See https://en.wikipedia.org/wiki/File:Linkage_four_bar_fixed.svg
% The resulting trajectories vary quite widely.  We will limit the scope of
% our problem to a crank-rocker mechanism.  This means:
% 1. Link a (driven link) is the shortest link     (a <= min(b,c,d))
% 2. Link b (connecting link) is the longest link  (b >= max(a,c,d))
% 3. Link a must be able to rotate 180 degrees     (a+b <= c+d)

a_set = linspace(min(c,d),0.1,15);  % Condition 1
b_set = linspace(max(c,d),0.3,2);   % Condition 2

% Open model
model = 'sm_four_bar_optim';
open_system(model)

% Define conditions for simulations
numSims = 0;
for ai=1:length(a_set)
    for bi=1:length(b_set)
        if( (a_set(ai)+b_set(bi)) <= (c+d) ) % Condition 3 above for desired case
            numSims=numSims+1;
            simInput(numSims) = Simulink.SimulationInput(model);
            simInput(numSims) = simInput(numSims).setVariable('a',a_set(ai));
            simInput(numSims) = simInput(numSims).setVariable('b',b_set(bi));
        end
    end
end

%% Run simulations
% Faster results if Fast Restart is on, Visualization off
%set_param(model,'FastRestart','on');
%set_param(model,'SimMechanicsOpenEditorOnUpdate','off');
%save_system(model); % Necessary for parallel simulations only

%tic;
simOut = sim(simInput,'ShowProgress','off','UseFastRestart','on');
%toc;

%% Plot trajectories
sm_four_bar_optim_param_sweep_plot

%% Reset model, close parallel pool
%set_param(model,'FastRestart','off');
%set_param(model,'SimMechanicsOpenEditorOnUpdate','on');
%save_system(model);

delete(gcp('nocreate'))  % Close parallel sessions if exist

