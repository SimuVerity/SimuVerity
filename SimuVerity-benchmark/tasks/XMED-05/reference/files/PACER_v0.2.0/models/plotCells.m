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
%Before run the script, please load Cells.mat first
load('N3Cfg.mat')
s=[4 8 9 10 11];% Specify the node number you want to print out
tstart=0;% s Specify the start time
tend=4.5;% s Specify the end time
col_start=find(cells(1,:)<=tstart*1000,1,'last');
col_end=find(cells(1,:)>=tend*1000,1,'first');
if isempty(col_start) || isempty(col_end)
    error('Time span is out of range.');
    exit;
else
    figure;
    ln=length(s);
    m=0;
    ax=zeros(1,ln);
    set(0, 'DefaultAxesColorOrder', [0.0 0.0 0.0]); %black
    hold all;
    margins=[0.02 0.03];
    for i=s %iterates through node list
        m=m+1;
        mtitle=Node_name{i,1};
        ax(1,m)=subtightplot(ln,1,m,margins);
        plot(ax(1,m),(cells(1,col_start:col_end)./1000),cells((i-1)*5+3,col_start:col_end));
        hold on;
        h = gca;
        h.Box=('off');
        ylabel([mtitle '(mV)']);
        xlabel('Time(s)');
    end
    set(0, 'DefaultAxesColorOrder', 'factory');
end