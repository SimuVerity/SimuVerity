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
clear;
warning off;
md='AV';
path_var=pwd;
mdl=[path_var filesep md];
simdata='AV_trace';
%%
%Simulate the model with different parameters
load_system(mdl)
open_system(mdl)
set_param(md,'Solver','ode1');
paramNameValStruct.AbsTol         = '1e-5';
paramNameValStruct.SaveState      = 'off';
paramNameValStruct.SaveTime ='off';
paramNameValStruct.SaveOutput     = 'off';
paramNameValStruct.SignalLogging='off';
paramNameValStruct.SimulationMode ='accelerator';
paramNameValStruct.ZeroCross ='on';
paramNameValStruct.StopTime='20000000';
paramNameValStruct.SolverType= 'Fixed-step';
paramNameValStruct.FixedStep='0.1';
mdlWks = get_param(md,'ModelWorkspace'); % Get the workspace variables
start_p=6; % start_p cycles later, external pacing starts
stop_p=10; % stop_p cycles later since the pacing stops, the simulation terminates.

duration=[30];
ndu=length(duration);

rate=[600]; 
q=length(rate);

bclall=[2300];
nbcl=length(bclall);

erpall=[160];
nerp=length(erpall);

%hall=[0.2 0.3];
hall=[0.1 0.05];
nh=length(hall);

%fall=[1.0 1.3 1.6];
fall=[0.7];
nf=length(fall);

mall=[3]; 
nm=length(mall);

sall=[7];
ns=length(sall);

%Vhall=[-3];
Vhall=[-8];
nVh=length(Vhall);

%jall=[0];
jall=[2];
nj=length(jall);

hsall=[35];
nhs=length(hsall);

hrall=[0.1];
nhr=length(hrall);

rall=[0.1];
nr=length(rall);

nfiles=ndu*q*nbcl*nerp*nh*nf*nm*ns*nVh*nj*nhs*nhr*nr;
datapp=zeros(nfiles,17);

cn0=start_p;
cn1=stop_p;
assignin(mdlWks,'cn0',cn0);
assignin(mdlWks,'cn1',cn1);
n=0;
for r=rall
    assignin(mdlWks,'r',r);
    for erp=erpall
        assignin(mdlWks,'erp',erp);
        for h=hall
            assignin(mdlWks,'h',h);
            for f=fall
                assignin(mdlWks,'f',f);
                for m=mall
                    assignin(mdlWks,'m',m);
                    for s=sall
                        assignin(mdlWks,'s',s);
                        for Vh=Vhall
                            assignin(mdlWks,'Vh',Vh);
                            for j=jall
                                assignin(mdlWks,'j',j);
                                for hs=hsall
                                    assignin(mdlWks,'hs',hs);
                                    for hr=hrall
                                        assignin(mdlWks,'hr',hr);
                                        for bcl=bclall
                                            assignin(mdlWks,'bcl',bcl);
                                            for du=duration
                                                assignin(mdlWks,'du',du);
                                                for pacing=rate
                                                    assignin(mdlWks,'pacing',pacing);
                                                    n=n+1;
                                                    simOut = sim(mdl,paramNameValStruct);
                                                    load('aprecord.mat');
                                                    filename=sprintf('%s_%d.mat',simdata,n);
                                                    save(filename,'aprecord');
                                                    
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end
close_system(mdl,0);

