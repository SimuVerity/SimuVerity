%% Description: 
% This script optimizes the model following these steps: 
% - The model will be optimized using surrogateopt
% - A chosen set of parameters will be changed during optimization
% - The aim is to change the parameters to reduce vehicle consumption
% - Vehicle consumption is defined as a combined consumption of two scenario (summer cycle and winter cycle)
% - While optimizing, it has to be ensured that the battery and the cabin reach a target temperature within a given amount of time
%-----------------
% Copyright 2022-2025 The MathWorks, Inc.
%-----------------

%% 1) Initialize model:
clear; 
modelName = checkModel('BEV_Thermal_Management');

% Switch to the optimization folder, where the results will be stored
cd(fileparts(which(mfilename)))

%% 2) Set up optimization options
% Max number of function calls. Afterwards surrogateopt will stop
maxfun = 20;                            

%          GbxRatio | Evap | Chill | Conds |Plate| Heat |  PTC  |    
lb        = [5,       0.5,   0.002,   1,    0.004,   1,     1,  ];  % Lower bound for the chosen variables
ub        = [11,       1,    0.005,   1.4,  0.012,   7,     4,  ];  % Upper bound for the chosen variables

% The 5th and 6th variable (PTC-Heater Power and Heater Power) are discrete variables
intgCond  = [6 7];     
% PTC Power = [1, 2, 3, 4] corresponds to [2000 2500 3000 3500] Watt -> see surrOptObjFcn
% Heat Power= [1, 2, 3, 4, 5, 6, 7] corresponds to [4000 4250 4500 4750 5000 5250 5500] Watt -> see surrOptObjFcn

% The surrogate points required 
minPtsSur = 25;            

% Set up the optimizer options:
options = optimoptions(@surrogateopt,'PlotFcn',@surrogateoptplot,'Display', 'testing', ...
                       'InitialPoints', [],'MinSurrogatePoints', minPtsSur,...
                       'MaxFunctionEvaluation',maxfun);

%% 3) Optimize
% Call surrogateopt will all available outputs (see documentation for more info on the outputs)
[x,fval,exitflag,output,trials] = surrogateopt(@surrOptObjFcn,lb,ub,intgCond,[],[],[],[],options);
    
%% 4) Save the results
% Save optimization results in the designated solver with a unique (date-based) identifier
proj = currentProject;
saveLabel = datestr(now,'YYmmDD_hhMM');
saveFolder = [pwd filesep 'results' filesep];

% Save the results in the folder
try
    save([saveFolder,'surrogateopt_',saveLabel],'trials','x','fval','output','exitflag');
catch
    disp('The "results" folder does not exist and is purposely put under gitignore (to avoid loading big data to Git). Create a result folder locally')
end
toc

%% 5) Plot results
postproOptim(trials,x)
