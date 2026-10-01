% Copyright 2025 Weiwei Ai, University of Auckland.
% 
% Licensed under the Apache License, Version 2.0 (the "License");
% you may not use this file except in compliance with the License.
% You may obtain a copy of the License at
% 
%     http://www.apache.org/licenses/LICENSE-2.0
% 
% Unless required by applicable law or agreed to in writing, software
% distributed under the License is distributed on an "AS IS" BASIS,
% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
% See the License for the specific language governing permissions and
% limitations under the License.
%%
%%Read excel data; If 'N3Cfg.mat' and 'N3Data.mat' already exist, this part
%%can be skipped.
filexls='Heart_N3_second_138N477P106VM'; % The excel file name
rootPath=fileparts(fileparts(fileparts(mfilename('fullpath'))));% change it according to your directory structure
addpath([rootPath,filesep 'models_refine']);
path_var=[rootPath,filesep 'models_refine']; % the path where the model will be saved
% Specify the range of reading
Noderange='A2:AW139';
Node_P_range='D1:AW1'; % the parameter names
Pathrange='A2:O478';
Path_P_range='E1:O1'; % the parameter names
Proberange='A2:E9';
% contains all configurations of heart model, which will be used to build a new heart model
filename= [path_var,filesep,'N3Cfg_second_138N477P106VM.mat']; 
% contains all parameters of heart model, which will be used for simulation
datafile=[path_var,filesep,'N3Data_second_138N477P106VM.mat']; 
[Node,Node_name,Node_pos,Path,Path_name,Probe,Probe_name,Probe_pos,cfgports]=PreCfgfcn_second(filexls,Noderange,Node_P_range,Pathrange, Path_P_range, Proberange,filename,datafile);

%% Choose Nodes/Path library and build a heart model,which will be saved to the systempath.
% library = [rootPath,filesep 'Lib' filesep 'Libs_second'];% the components library path
% node_n = 'Libs_second/Node_N_V6'; % The N type cell model library
% node_m = 'Libs_second/Node_M_V4'; % The M type cell model library
% node_nm = 'Libs_second/Node_NM_V4'; % The NM type cell model library
% path = 'Libs_second/Path_V3'; % The path model library
% probe='Libs_second/Electrode'; % The EGM generation model library
% HeartModel='Heart_138N477P106VM'; % The name of the heart model
% Buildmodel_fcn(HeartModel,filename,node_n,node_m,node_nm,path,probe,path_var,library);
