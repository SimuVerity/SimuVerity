% Optimization tune four-bar linkage to follow a desired trajectory
% Copyright 2017-2025 MathWorks, Inc.

% Set up model
mdl = 'sm_four_bar_optim';
load_system(mdl);

% Fixed Parameters
c = 0.2;  % m
d = 0.25; % m
h = 0.2;  % m

% Initial values for tuned parameters
% Length of the crank and connecting link
a = 0.18; % m
b = 0.25; % m
x0=[a b]; 

% Load desired results
load sm_four_bar_optim_des;

% Shift trajectory so that min(x)=0, min(y)=0;
xy_pos_des = xy_pos_des-min(xy_pos_des); 

%% Obtain initial trajectory
simOut_orig=sim(mdl);
simOut_xy_pos = simOut_orig.logsout_sm_four_bar_optim.get('xy_pos');
xy_pos_orig = simOut_xy_pos.Values.Data;
pause(2);

%% Plot initial and desired results
% Create figure
if ~exist('h3_sm_four_bar_optim', 'var') || ...
        ~isgraphics(h3_sm_four_bar_optim, 'figure')
    h3_sm_four_bar_optim = figure('Name', 'sm_four_bar_optim');
end
figure(h3_sm_four_bar_optim)
clf(h3_sm_four_bar_optim)

% Plot data
sm_four_bar_optim_plottraj(xy_pos_des,xy_pos_orig,[],h3_sm_four_bar_optim);
title('Trajectory Optimization');
legend({'Desired','Initial'});
pause(2);

%% Set up optimization problem

% Define upper bounds, lower bounds, and constraints
%
% Four-bar linkages can be grouped into various cases based on the lengths
% of their links.  See https://en.wikipedia.org/wiki/File:Linkage_four_bar_fixed.svg
% The resulting trajectories vary quite widely.  We will limit the scope of
% our problem to a crank-rocker mechanism.  This means: 
% 1. Link a (driven link) is the shortest link     (a <= min(b,c,d))
% 2. Link b (connecting link) is the longest link  (b >= max(a,c,d))
% 3. Link a must be able to rotate 180 degrees     (a+b <= c+d)

LB = [0.1  max(c,d)];  % Condition 1
UB = [min(c,d) 0.3];   % Condition 2

% Constraints are defined in the form of Ax <= b
Am=[1 1];
bm=[c+d];

%% Configure model for fast simulation
set_param(mdl,'FastRestart','on');
%set_param(mdl,'SimMechanicsOpenEditorOnUpdate','off');
%save_system(mdl); % Necessary for parallel exec only
sm_four_bar_optim_vistraj(bdroot,'show')

%% Run optimization
% Set up figure to watch progress of optimization
if ~exist('h4_sm_four_bar_optim', 'var') || ...
        ~isgraphics(h4_sm_four_bar_optim, 'figure')
    h4_sm_four_bar_optim = figure('Name', 'sm_four_bar_optim');
end
figure(h4_sm_four_bar_optim)
clf(h4_sm_four_bar_optim)

% Add reference trajectory
sm_four_bar_optim_plottraj(xy_pos_des,xy_pos_orig,[],h4_sm_four_bar_optim)
title('Trajectory Optimization');
legend({'Desired','Initial'});
hold on;
title('Trajectory Optimization Progress');

pause(4)

options = optimoptions('patternsearch','PollMethod','GSSPositiveBasis2N', ...
    'Display','iter','PlotFcn', @psplotbestf,'MaxIterations',40, ...
    'MeshTolerance',0.001,'UseCompletePoll',true,'InitialMeshSize',mean(x0), ...
    'MeshContractionFactor',0.25);

% Options to terminate early
%,'MaxIterations',40

% Parallel computing on/off
% Change value and re-run this section of script only to see effect
options.UseParallel = false;

% Run optimization
tic;
[x,fval,exitflag,output] = ...
    patternsearch(@(x)obj_sm_four_bar_optim_match_path(mdl,x,xy_pos_des(:,1),xy_pos_des(:,2),h4_sm_four_bar_optim),...
    x0,Am,bm,[],[],LB,UB,[],options);

Elapsed_Sim_Time = toc;
disp(['Elapsed Time = ' num2str(Elapsed_Sim_Time)]);

%% Plot initial and final results 

% Set workspace values to values obtained from optimization
a=x(1); b=x(2);

% Display values to command window
Initial = []; Final = []; Link = {'a'; 'b'};
for i=1:length(x0)
    Initial{i,1} = sprintf('%0.4f',x0(i));
    Final{i,1} = sprintf('%0.4f',x(i));
end
results = table(Link,Initial,Final);
disp(results)

% Undo settings for fast simulation so we can see animation
set_param(mdl,'FastRestart','off');
set_param(mdl,'SimMechanicsOpenEditorOnUpdate','on');
%save_system(mdl); % Necessary for parallel exec only
delete(gcp('nocreate'))  % Close parallel sessions if exist

% Overlay final trajectory
simOut_final=sim(mdl);
simOut_xy_pos = simOut_final.logsout_sm_four_bar_optim.get('xy_pos');
xy_pos_final = simOut_xy_pos.Values.Data;

sm_four_bar_optim_plottraj(xy_pos_des,xy_pos_orig,xy_pos_final,h3_sm_four_bar_optim);
legend({'Desired','Initial','Optimized'});
title('Trajectory Optimization');

% Hide original trajectory
sm_four_bar_optim_vistraj(bdroot,'hide')
