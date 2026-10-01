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
load('AV_trace_2.mat');
figure;
set(0, 'DefaultAxesColorOrder', [0.0 0.0 0.0]); %black

plot((aprecord(1,:)./1000),aprecord(3,:));
axis([0 70 -20 80]);
h = gca;
h.YTick = [-20 0 60];
xlabel('Time(s)');
ylabel('mV');
hold on;
x=0:30:600;
y=zeros(length(x),1);
plot(x,y,':');
hold on;
x=0:30:600;
y=zeros(length(x),1)-5.6;
plot(x,y,':');
set(0, 'DefaultAxesColorOrder', 'factory');
%grid on;
