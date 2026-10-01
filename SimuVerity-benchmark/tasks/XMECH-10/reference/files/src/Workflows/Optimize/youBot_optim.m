function [t, QOpt, Q0] = youBot_optim(modelname, YBT_Par, t, Q0)
% Copyright 2016-2025 The MathWorks, Inc.

%% Configure model
set_param([modelname '/Input'],'OverrideUsingVariant','Splines');
set_param([modelname '/Arm/Environment/Gripper Force'],'OverrideUsingVariant','Payload');
set_param([modelname '/Arm/Actuation'],'OverrideUsingVariant','Motion');
set_param(modelname,'SimMechanicsOpenEditorOnUpdate','off');
set_param(modelname,'FastRestart','on'); 

%% Store initial trajectory
Qt = Q0;
numJoints = size(Q0,1); 

% Adjust only middle points - leave end points as defined
numPoints = length(t)-2; 


%% Set optimization problem
% Num Optimization variables = numJoints * numViaPoints
xOld = [];  % tracks previous optimal values
yout = [];  % simulation output
iter = 0;

% Set cost function
fun = @(x) costFunTrajectoryPlanning(x);

% Create initial optimization vector from spline matrix
% Select via points from Q matrix and expand into vector
% [Q0(:,2);Q0(:,3);Q(:,4),...];
x0 = Q0(:,2:numPoints+1);
x0 = x0(:);

nonlcon = [];
A = [];
b = [];
Aeq = [];
beq = [];
lb = [];
ub = [];

lb(1) = rad2deg(YBT_Par.Pivot.Motor.range(1));
lb(2) = rad2deg(YBT_Par.Bicep.Motor.range(1));
lb(3) = rad2deg(YBT_Par.Forearm.Motor.range(1));
lb(4) = rad2deg(YBT_Par.Wrist.Motor.range(1));
ub(1) = rad2deg(YBT_Par.Pivot.Motor.range(2));
ub(2) = rad2deg(YBT_Par.Bicep.Motor.range(2));
ub(3) = rad2deg(YBT_Par.Forearm.Motor.range(2));
ub(4) = rad2deg(YBT_Par.Wrist.Motor.range(2));

lb = repmat(lb',numPoints,1);
ub = repmat(ub',numPoints,1);

options = psoptimset('Vectorized','off','Display','iter','UseParallel','never',...
    'TolMesh',0.0025,'CompletePoll','on','InitialMeshSize',0.05,'ScaleMesh','on',...
    'PlotFcns', @psplotbestf,'MaxFunEvals',50); % SHORT

%    'PlotFcns', @psplotbestf,'MaxIter',3); % VERY SHORT
%    'PlotFcns', @psplotbestf,'MaxFunEvals',50); % SHORT
%    'PlotFcns', @psplotbestf,'MaxIter',75); % COMPLETE

% VERY SHORT: ,'MaxIter',3
% SHORT: ,'MaxFunEvals',50
% COMPLETE: ,'MaxIter',75

[xOpt, ~, ~, ~] = ...
    patternsearch(fun,x0,A,b,Aeq,beq,lb,ub,nonlcon, ...
        options);

    
% Convert optim vector to spline matrix
xOpt = reshape(xOpt, numJoints, numPoints);
QOpt = Q0;
QOpt(:,2:numPoints+1) = xOpt;

% Reset global model configurations
set_param(modelname,'FastRestart','off'); 
set_param(modelname,'SimMechanicsOpenEditorOnUpdate','on');

if (YBT_Par.Pivot.Motor.friction==0)
    assignin('base','EE_xyz_opt_friction','low');
else
    assignin('base','EE_xyz_opt_friction','high');
end

evalin('base','youBot_optim_plotEExyz');

datestringfile = datestr(now,'yymmddHHMM');
assignin('base','Q0',Q0);
assignin('base','QOpt',QOpt);
assignin('base','Q0',Q0);
evalin('base',['save youBot_optres_' datestringfile ' EE_xyz_opt t Q0 QOpt EE_xyz_opt_friction']);


%% Objective function: minimize Torque effort
function [f] = costFunTrajectoryPlanning(x)
        updateIfNeeded(x);      
        % f = yout(end,1);      % tauCost;
        %f = yout.getElement('torqueCost').Values.Data(end,1);
        f = yout;
        
end

%% Helper function to run simulation only when needed
% See: http://www.mathworks.com/help/optim/ug/example-using-fminimax-with-a-simulink-model.html
function updateIfNeeded(x)
     if ~isequal(x,xOld) % compute only if needed
        iter = iter+1; 
        % Map optimization vector to spline matrix
        Xvp = reshape(x, numJoints, numPoints);
        Qt(:,2:numPoints+1) = Xvp;    

        % Run simulation
        %simOut = sim(modelname, 'SrcWorkspace', 'current',...
        %    'StopTime', num2str(totalTime));
        simOut = sim(modelname, 'SrcWorkspace', 'current',...
            'StopTime', '3.3');

        % Get Torque Cost function from matrix. 
        % outputs: [torqueCost(1x1), dist2obj1(1x1)]
        logsout_youBot_Arm = simOut.get('logsout_youBot_Arm');
        %tcst = logsout_youBot_Arm.get('torque_cost');
        tcst = logsout_youBot_Arm.get('electrical_cost');
        yout = tcst.Values.Data;

        %disp(num2str(x))
        evalin('base',['x_opttest(' num2str(iter) ',:) = [' num2str(x') '];' ]);
        assignin('base','EE_xyz_out', simOut.get('EE_xyz'));
        evalin('base',['EE_xyz_opt(' num2str(iter) ').time = EE_xyz_out.time;' ]);
        evalin('base',['EE_xyz_opt(' num2str(iter) ').signals = EE_xyz_out.signals;' ]);
        evalin('base',['EE_xyz_opt(' num2str(iter) ').cost = ' num2str(yout) ';' ]);
        
        xOld = x;
                
     end
end
end
