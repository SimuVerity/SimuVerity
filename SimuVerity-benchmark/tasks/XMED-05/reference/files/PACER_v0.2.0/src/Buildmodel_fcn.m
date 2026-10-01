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
function Buildmodel_fcn(HeartModel,filename,node_n,node_m,node_nm,path,probe,systempath,library)

bdclose('all'); %closes any open Simulink windows

%% Load model parameters
dims=load(filename);
Node=dims.Node;
Node_name=dims.Node_name;
Path_name=dims.Path_name;
outputs=dims.cfgports;
Heart=HeartModel;

%% Model Setup
simulink;
open_system(library);
open_system(new_system(Heart)); % modelType is the name of the .mat file

%Model Spacing Values
topMargin = 30;
leftMargin=110;
nodeSpacing = 100;
pathSpacing = 100;
tagSpacing=20;
tagl=75; % tag x length
tagw=20; % tag y length

%% Create the subsystem Heart (Container)
 left_corner=[leftMargin,topMargin];
 l=200;
 w=300;
 block_name=sprintf('%s/%s',Heart,'Heart'); %node_name comes from the setup script
 add_block('simulink/Ports & Subsystems/Subsystem',block_name); %adds block to model canvas
 set_param(block_name,'Position',[left_corner(1) left_corner(2) left_corner(1)+l left_corner(2)+w]);
 Heart=sprintf('%s/%s',Heart,'Heart');
 
 delete_line(Heart, 'In1/1', 'Out1/1');
 delete_block(sprintf('%s/%s',Heart,'In1'));
 delete_block(sprintf('%s/%s',Heart,'Out1')); 
%% Node Assembly
for i=1:size(Node,1) %iterates through node list
    % Which type of node
    if strcmp(Node_name{i,2},'M')
        node=node_m;
    else if strcmp(Node_name{i,2},'N')
            node=node_n;
        else if strcmp(Node_name{i,2},'NM')
                node=node_nm;
            else
                error('The dimension of Nodecfg does not match');
            end
        end
    end
    
    % Puts all nodes in first column, each shifted accordingly
    left_corner=[leftMargin,(topMargin + (i-1)* nodeSpacing)];
    l=70;%The xlength of the block
    w=60; %The ylength of the block
    
    % Add Node
    block_name=Node_name{i,1};
    myblock=sprintf('%s/%s',Heart,block_name); %node_name comes from the setup script
    add_block(node,myblock); %adds block to model canvas
    set_param(myblock,'Position',[left_corner(1) left_corner(2) left_corner(1)+l left_corner(2)+w]);
    
    % Add output tag
    port=1;
    initYOffset = (w/port)/2-(tagw/2); %initial Y offset for output tags 
    x0=left_corner(1)+l+15;
    y0=left_corner(2)+initYOffset;
    % Add output1 tag to path
    tagname=sprintf('Cell_%d',i);
    out_name=sprintf('%s/%s',Heart,tagname);
    add_block('simulink/Signal Routing/Goto',out_name);
    set_param(out_name,'Position',[x0 y0 x0+tagl y0+tagw],'ShowName','off','GotoTag',tagname);
    outport_num=1;
    inport_num=1;
    add_line(Heart,sprintf('%s/%d',block_name,outport_num),sprintf('%s/%d',tagname,inport_num));
    
    % Add input tag
    port=2;
    initYOffset = (w/port)/2-(tagw/2); %initial Y offset for output tags
    x0=left_corner(1)-(tagl+15);
    y0=left_corner(2)+initYOffset;
    
    % add input1 tag for parameters
    tagname=sprintf('Para_%d',i);
    in_name=sprintf('%s/%s',Heart,tagname);
    add_block('simulink/Signal Routing/From',in_name);
    set_param(in_name,'Position',[x0 y0 x0+tagl y0+tagw],'ShowName','off','GotoTag',tagname);
    outport_num=1;
    inport_num=1;
    add_line(Heart,sprintf('%s/%d',tagname,outport_num),sprintf('%s/%d',block_name,inport_num));
       
    % add input2 tag from paths
    tagname=sprintf('Path_%d',i);
    in_name=sprintf('%s/%s',Heart,tagname);
    add_block('simulink/Signal Routing/From',in_name);
    y0=y0+(w/port);
    set_param(in_name,'Position',[x0 y0 x0+tagl y0+tagw],'ShowName','off','GotoTag',tagname);
    outport_num=1;
    inport_num=2;
    add_line(Heart,sprintf('%s/%d',tagname,outport_num),sprintf('%s/%d',block_name,inport_num));
end
%% Path Assembly
joint=cell(1,size(Node,1));
leftMargin=leftMargin+270;

for i=1:size(Path_name,1)    
    % Block positioning   
    left_corner=[leftMargin,(topMargin + (i-1) * pathSpacing)];
    l=120; %The xlength of the block
    w=80; %The ylength of the block
    
    % Add block
    block_name=strcat(Path_name{i,1},'_',Path_name{i,2});%Path_name comes from the setup script
    myblock=sprintf('%s/%s',Heart,block_name); 
    add_block(path,myblock);
    set_param(myblock,'Position',[left_corner(1) left_corner(2) left_corner(1)+l left_corner(2)+w]);
       
    % Find the two end cells of the path
    celli=find(ismember (Node_name(:,1),Path_name{i,1}));
    cellj=find(ismember (Node_name(:,1),Path_name{i,2}));
    
    % Add output tags
    port=3;
    initYOffset = (w/port)/2-(tagw/2); %initial Y offset for output tags 
    x0=left_corner(1)+l+15;
    y0=left_corner(2)+initYOffset;
    
    % Add Output1 Cellj2i Tags and connect it with the corresponding joint
    tagname=sprintf('Cellj2i_%d',i);
    out_name=sprintf('%s/%s',Heart,tagname);
    add_block('simulink/Signal Routing/Goto',out_name);
    set_param(out_name,'Position',[x0 y0 x0+tagl y0+tagw],'ShowName','off','GotoTag',tagname);
    outport_num=1;
    inport_num=1;
    add_line(Heart,sprintf('%s/%d',block_name,outport_num),sprintf('%s/%d',tagname,inport_num));
    tempt=cell(1);
    tempt{1}=tagname;
    joint{celli}=vertcat(joint{celli},tempt);
   
    % Add Output2 Celli2j Tags
    tagname=sprintf('Celli2j_%d',i);
    out_name=sprintf('%s/%s',Heart,tagname);
    add_block('simulink/Signal Routing/Goto',out_name);
    y0=y0+(w/port);
    set_param(out_name,'Position',[x0 y0 x0+tagl y0+tagw],'ShowName','off','GotoTag',tagname);
    outport_num=2;
    inport_num=1;
    add_line(Heart,sprintf('%s/%d',block_name,outport_num),sprintf('%s/%d',tagname,inport_num));
    tempt=cell(1);
    tempt{1}=tagname;
    joint{cellj}=vertcat(joint{cellj},tempt);
    
     % Add output3 tag to Probes
    tagname=sprintf('ToProbe_%d',i);
    out_name=sprintf('%s/%s',Heart,tagname); 
    add_block('simulink/Signal Routing/Goto',out_name);
    y0=y0+(w/port);
    set_param(out_name,'Position',[x0 y0 x0+tagl y0+tagw],'ShowName','off','GotoTag',tagname);
    outport_num=3;
    inport_num=1;
    add_line(Heart,sprintf('%s/%d',block_name,outport_num),sprintf('%s/%d',tagname,inport_num));
        
    % Add input tags   
    port=3;
    initYOffset = (w/port)/2-(tagw/2); %initial Y offset for output tags
    x0=left_corner(1)-(tagl+15);
    y0=left_corner(2)+initYOffset;
    
    % Add Input1 Parameter Tags
    tagname=sprintf('Pcfg_%d',i);
    in_name=sprintf('%s/%s',Heart,tagname);
    add_block('simulink/Signal Routing/From',in_name);
    set_param(in_name,'Position',[x0 y0 x0+tagl y0+tagw],'ShowName','off','GotoTag',tagname);
    outport_num=1;
    inport_num=1;
    add_line(Heart,sprintf('%s/%d',tagname,outport_num),sprintf('%s/%d',block_name,inport_num));
           
    % Add Input2 Cell_i Tags and connect it with the corresponding cell
    tagname=sprintf('Cell_i_%d',i);
    in_name=sprintf('%s/%s',Heart,tagname);
    add_block('simulink/Signal Routing/From',in_name);
    y0=y0+(w/port);
    set_param(in_name,'Position',[x0 y0 x0+tagl y0+tagw],'ShowName','off','GotoTag',sprintf('Cell_%d',celli));
    outport_num=1;
    inport_num=2;
    add_line(Heart,sprintf('%s/%d',tagname,outport_num),sprintf('%s/%d',block_name,inport_num));
        
    % Add Input3 Cell_j Tags and connect it with the corresponding cell
    tagname=sprintf('Cell_j_%d',i);
    in_name=sprintf('%s/%s',Heart,tagname);
    add_block('simulink/Signal Routing/From',in_name);
    y0=y0+(w/port);
    set_param(in_name,'Position',[x0 y0 x0+tagl y0+tagw],'ShowName','off','GotoTag',sprintf('Cell_%d',cellj));
    outport_num=1;
    inport_num=3;
    add_line(Heart,sprintf('%s/%d',tagname,outport_num),sprintf('%s/%d',block_name,inport_num));      
end

%% Probe Assembly
leftMargin=leftMargin+320; % Move to the right of 320
for i=1:size(Path_name,1)  
    % Block positioning   
    left_corner=[leftMargin,(topMargin + (i-1) * pathSpacing)];
    l=120; %The xlength of the block
    w=80; %The ylength of the block
    
    % Add block
    block_name=strcat(Path_name{i,1},'_',Path_name{i,2},'_');%Probe_attached to a path
    myblock=sprintf('%s/%s',Heart,block_name);
    add_block(probe,myblock);
    set_param(myblock,'Position',[left_corner(1) left_corner(2) left_corner(1)+l left_corner(2)+w]);
    
    % Add output tags
    port=2;
    initYOffset = (w/port)/2-(tagw/2); %initial Y offset for output tags 
    x0=left_corner(1)+l+15;
    y0=left_corner(2)+initYOffset;
    
    % Add Output1 EGM_i Tags
    tagname=sprintf('EGM_%d',i);
    out_name=sprintf('%s/%s',Heart,tagname);
    add_block('simulink/Signal Routing/Goto',out_name);
    set_param(out_name,'Position',[x0 y0 x0+tagl y0+tagw],'ShowName','off','GotoTag',tagname);
    outport_num=1;
    inport_num=1;
    add_line(Heart,sprintf('%s/%d',block_name,outport_num),sprintf('%s/%d',tagname,inport_num));
      
    % Add Output2 wave_i Tags
    tagname=sprintf('wave_%d',i);
    out_name=sprintf('%s/%s',Heart,tagname);
    add_block('simulink/Signal Routing/Goto',out_name);
    y0=y0+(w/port);
    set_param(out_name,'Position',[x0 y0 x0+tagl y0+tagw],'ShowName','off','GotoTag',tagname);
    outport_num=2;
    inport_num=1;
    add_line(Heart,sprintf('%s/%d',block_name,outport_num),sprintf('%s/%d',tagname,inport_num));
            
    % Add input tags   
    port=2;
    initYOffset = (w/port)/2-(tagw/2); %initial Y offset for output tags
    x0=left_corner(1)-(tagl+15);
    y0=left_corner(2)+initYOffset;
    
    % Add Input1 FromPath_i Tags
    tagname=sprintf('FromPath_%d',i);
    in_name=sprintf('%s/%s',Heart,tagname);
    add_block('simulink/Signal Routing/From',in_name);
    outport_num=1;
    inport_num=1;
    add_line(Heart,sprintf('%s/%d',tagname,outport_num),sprintf('%s/%d',block_name,inport_num));  
    tagname=sprintf('ToProbe_%d',i);
    set_param(in_name,'Position',[x0 y0 x0+tagl y0+tagw],'ShowName','off','GotoTag',tagname);
   
    % Add Input2 Leads Tags and connect it with the corresponding cell
    tagname=sprintf('Leads_%d',i);
    in_name=sprintf('%s/%s',Heart,tagname);
    add_block('simulink/Signal Routing/From',in_name);
    y0=y0+(w/port);
    outport_num=1;
    inport_num=2;
    add_line(Heart,sprintf('%s/%d',tagname,outport_num),sprintf('%s/%d',block_name,inport_num));  
    tagname=sprintf('Leads');
    set_param(in_name,'Position',[x0 y0 x0+tagl y0+tagw],'ShowName','off','GotoTag',tagname);
end

%% add joint output tags
orTop=0;
leftMargin=leftMargin+240;
for i=1:size(Node,1)
  
    numIns=length(joint{i}); 
    left_corner=[leftMargin,(topMargin + orTop)];
    if strcmp(Node_name{i,1},'RA')|| strcmp(Node_name{i,1},'RVA')
        orTop = orTop + tagSpacing * (numIns+1)+15;
    else
        orTop = orTop + tagSpacing * numIns+15;
    end     
    % Use summation block if multiple inputs
        x0=left_corner(1)+90;
        if strcmp(Node_name{i,1},'RA')|| strcmp(Node_name{i,1},'RVA')
        y0=left_corner(2)+(tagSpacing * (numIns+1)/2)-10;
        op_name=sprintf('%s/Node%d_OR',Heart,i);      
        if (numIns+1) > 1
        add_block('simulink/Math Operations/Sum',op_name);
        set_param(op_name,'Inputs',num2str(numIns+1),'Position',[x0 y0 x0+tagw y0+tagw]);
        end
        else
        y0=left_corner(2)+(tagSpacing * numIns/2)-10;
        op_name=sprintf('%s/Node%d_OR',Heart,i);      
        if (numIns) > 1
        add_block('simulink/Math Operations/Sum',op_name);
        set_param(op_name,'Inputs',num2str(numIns),'Position',[x0 y0 x0+tagw y0+tagw]);
        end   
        end
        
     % add output tag to paths
        out_name=sprintf('%s/Path%d',Heart,i);
        add_block('simulink/Signal Routing/Goto',out_name);
        x1=x0+25;
        y1=y0;
        set_param(out_name,'Position',[x1 y1 x1+tagl y1+tagw],'ShowName','off','GotoTag',sprintf('Path_%d',i));

     % add input tags to the joint      
      for j=1:numIns
      out_name=sprintf('%s/Cell%d_%d',Heart,i,j);
      add_block('simulink/Signal Routing/From',out_name);
      temp=joint{i}(j);
      set_param(out_name,'GotoTag',temp{1});
      set_param(out_name,'ShowName','off');
      x0=left_corner(1);
      y0=left_corner(2)+ (j-1)*tagSpacing;
      set_param(out_name,'Position',[x0 y0 x0+tagl y0+tagw]);          
      if (numIns) > 1
      add_line(Heart,sprintf('Cell%d_%d/1',i,j),sprintf('Node%d_OR/%d',i,j)); 
      end
      end 
      
      if (numIns) > 1
       add_line(Heart,sprintf('Node%d_OR/1',i),sprintf('Path%d/1',i));
      end
      
      if strcmp(Node_name{i,1},'RA')
      out_name=sprintf('%s/AP',Heart);
      add_block('simulink/Signal Routing/From',out_name);
      set_param(out_name,'GotoTag','AP','ShowName','off');
      x0=left_corner(1);
      y0=left_corner(2)+ numIns*tagSpacing;
      set_param(out_name,'Position',[x0 y0 x0+tagl y0+tagw]); 
      add_line(Heart,sprintf('AP/1'),sprintf('Node%d_OR/%d',i,j+1)); 
      end
      
      if strcmp(Node_name{i,1},'RVA')
      out_name=sprintf('%s/VP',Heart);
      add_block('simulink/Signal Routing/From',out_name);
      set_param(out_name,'GotoTag','VP','ShowName','off');
      x0=left_corner(1);
      y0=left_corner(2)+ numIns*tagSpacing;
      set_param(out_name,'Position',[x0 y0 x0+tagl y0+tagw]);   
      add_line(Heart,sprintf('VP/1'),sprintf('Node%d_OR/%d',i,j+1)); 
      end
      
      if numIns==1 && ~strcmp(Node_name{i,1},'RVA') && ~strcmp(Node_name{i,1},'RA')
      add_line(Heart,sprintf('Cell%d_%d/1',i,1),sprintf('Path%d/1',i)); 
      end
end

%% Configuration input block     
    % Block positioning
    leftMargin=leftMargin+300;
    
    left_corner=[leftMargin,topMargin];
    l=5; % x length
    w=(tagSpacing)*(size(Node,1)+size(Path_name,1)+1)+20; % y length
    
    % Add cfg demux block
    block_name='Cfg';
    myblock=sprintf('%s/%s',Heart,block_name);
    add_block('simulink/Signal Routing/Demux',myblock);
    set_param(myblock,'Position',[left_corner(1) left_corner(2) left_corner(1)+l left_corner(2)+w]);
    set_param(myblock,'Outputs',outputs{1});
    
    % Add cfg inport block
    block_name='Cfgin';
    myblock=sprintf('%s/%s',Heart,block_name);
    add_block('simulink/Sources/In1',myblock);
    x0=left_corner(1)-65; %move to the left of 65
    y0=left_corner(2)+(w/2)-10;
    set_param(myblock,'Position',[x0 y0 x0+50 y0+tagw]);
    add_line(Heart,sprintf('Cfgin/1'),sprintf('Cfg/1'));
   
    % Add pacing inputs-----
    left_corner(2)=left_corner(2)+w+10;
    l=5; % x length
    w=(tagSpacing)*2+20; % y length
    
    % Add pacing demux block
    block_name1='Pacing';
    block_name=sprintf('%s/%s',Heart,block_name1);
    add_block('simulink/Signal Routing/Demux',block_name);
    set_param(block_name,'Position',[left_corner(1) left_corner(2) left_corner(1)+l left_corner(2)+w]);
    set_param(block_name,'Outputs','2');
    
    % Add pace inport block
    block_name1='Pace';
    block_name=sprintf('%s/%s',Heart,block_name1);
    add_block('simulink/Sources/In1',block_name);
    x0=left_corner(1)-65;
    y0=left_corner(2)+(w/2)-10;
    set_param(block_name,'Position',[x0 y0 x0+50 y0+tagw]);
    add_line(Heart,sprintf('Pace/1'),sprintf('Pacing/1'));
        
%% Connections to the configurations of cells and paths
    leftMargin=leftMargin+20;
for i=1:size(Node,1)
   % Positioning
    left_corner=[leftMargin,(topMargin + (i-1) * tagSpacing)];
    
   % add output tag for Node parameters
    out_name=sprintf('%s/Para%d',Heart,i);
    add_block('simulink/Signal Routing/Goto',out_name);
    x0=left_corner(1);
    y0=left_corner(2)+10;
    set_param(out_name,'Position',[x0 y0 x0+tagl y0+tagw]);
    set_param(out_name,'GotoTag',sprintf('Para_%d',i));
    set_param(out_name,'ShowName','off');
    add_line(Heart,sprintf('Cfg/%d',i),sprintf('Para%d/1',i));
        
end
for i=1:size(Path_name,1)
   % Positioning
    left_corner=[leftMargin,(topMargin + (size(Node,1)+i-1) * tagSpacing)];
    
   % add output tag for Node parameters
    out_name=sprintf('%s/Pcfg%d',Heart,i);
    add_block('simulink/Signal Routing/Goto',out_name);
    x0=left_corner(1);
    y0=left_corner(2)+10;
    set_param(out_name,'Position',[x0 y0 x0+tagl y0+tagw]);
    set_param(out_name,'GotoTag',sprintf('Pcfg_%d',i));
    set_param(out_name,'ShowName','off');
    add_line(Heart,sprintf('Cfg/%d',i+size(Node,1)),sprintf('Pcfg%d/1',i));
end  

% Positioning
    left_corner=[leftMargin,(topMargin + (size(Node,1)+size(Path_name,1)) * tagSpacing)];
    
     % add output tag for Leads parameters
    out_name=sprintf('%s/Leads',Heart);
    add_block('simulink/Signal Routing/Goto',out_name);
    x0=left_corner(1);
    y0=left_corner(2)+10;
    set_param(out_name,'Position',[x0 y0 x0+tagl y0+tagw]);
    set_param(out_name,'GotoTag',sprintf('Leads'));
    set_param(out_name,'ShowName','off');
    add_line(Heart,sprintf('Cfg/%d',size(Path_name,1)+size(Node,1)+1),sprintf('Leads/1'));
 
    left_corner=[leftMargin,(topMargin + (size(Node,1)+size(Path_name,1)+1) * tagSpacing)];
    
   % add output tag for AP
    out_name=sprintf('%s/APin',Heart);
    add_block('simulink/Signal Routing/Goto',out_name);
    x0=left_corner(1);
    y0=left_corner(2)+35;
    set_param(out_name,'Position',[x0 y0 x0+tagl y0+tagw]);
    set_param(out_name,'GotoTag',sprintf('AP'));
    set_param(out_name,'ShowName','off');
    add_line(Heart,sprintf('Pacing/%d',1),sprintf('APin/1'));

    % Positioning
    left_corner=[leftMargin,(topMargin + (size(Node,1)+size(Path_name,1)+2) * tagSpacing)];
    
   % add output tag for VP
    out_name=sprintf('%s/VPin',Heart);
    add_block('simulink/Signal Routing/Goto',out_name);
    x0=left_corner(1);
    y0=left_corner(2)+45;
    set_param(out_name,'Position',[x0 y0 x0+tagl y0+tagw]);
    set_param(out_name,'GotoTag',sprintf('VP'));
    set_param(out_name,'ShowName','off');
    add_line(Heart,sprintf('Pacing/%d',2),sprintf('VPin/1'));



 %% Output ports
    leftMargin=leftMargin+200;
    % Block positioning
    left_corner=[leftMargin,topMargin];
    l=10;
    w=(tagSpacing)*(size(Node,1))+20;
    
    % Add cellout Mux block
    block_name1='Cell_out';
    block_name=sprintf('%s/%s',Heart,block_name1);
    add_block('simulink/Signal Routing/Mux',block_name);
    set_param(block_name,'Position',[left_corner(1) left_corner(2) left_corner(1)+l left_corner(2)+w]);
    set_param(block_name,'Inputs',num2str(size(Node,1)));   
    set_param(block_name,'ShowName','off');
    % Add outport block
    block_name1='Cells_out';
    block_name=sprintf('%s/%s',Heart,block_name1);
    add_block('simulink/Sinks/Out1',block_name);
    x0=left_corner(1)+25;
    y0=left_corner(2)+(w/2)-10;
    set_param(block_name,'Position',[x0 y0 x0+50 y0+tagw],'Port','1');
    add_line(Heart,sprintf('Cell_out/1'),sprintf('Cells_out/1'));
    
    left_corner=[leftMargin,topMargin+w];
    l=10;
    w1=(tagSpacing)*size(Path_name,1)+20;
    
    % Add EGM out Mux block
    block_name1='EGM_out';
    block_name=sprintf('%s/%s',Heart,block_name1);
    add_block('simulink/Math Operations/Add',block_name);
    set_param(block_name,'Position',[left_corner(1) left_corner(2) left_corner(1)+l left_corner(2)+w1]);
    set_param(block_name,'Inputs',num2str(size(Path_name,1)));  
    set_param(block_name,'ShowName','off');
    % Add outport block
    block_name1='EGMs_out';
    block_name=sprintf('%s/%s',Heart,block_name1);
    add_block('simulink/Sinks/Out1',block_name);
    x0=left_corner(1)+25;
    y0=left_corner(2)+(w1/2)-10;
    set_param(block_name,'Position',[x0 y0 x0+50 y0+tagw],'Port','3');
    add_line(Heart,sprintf('EGM_out/1'),sprintf('EGMs_out/1'));
    
    left_corner=[leftMargin,topMargin+w+w1];
    l=10;
    w=(tagSpacing)*size(Path_name,1)+20; 
    
    % Add Wavefront Mux out block
    block_name1='Wave_out';
    block_name=sprintf('%s/%s',Heart,block_name1);
    add_block('simulink/Signal Routing/Mux',block_name);
    set_param(block_name,'Position',[left_corner(1) left_corner(2) left_corner(1)+l left_corner(2)+w]);
    set_param(block_name,'Inputs',num2str(size(Path_name,1)));  
    set_param(block_name,'ShowName','off');
    % Add outport block
    block_name1='Waves_out';
    block_name=sprintf('%s/%s',Heart,block_name1);
    add_block('simulink/Sinks/Out1',block_name);
    x0=left_corner(1)+25;
    y0=left_corner(2)+(w/2)-10;
    set_param(block_name,'Position',[x0 y0 x0+50 y0+tagw],'Port','2');
    add_line(Heart,sprintf('Wave_out/1'),sprintf('Waves_out/1'));
%% Connect cells/ToProbe to the output ports

leftMargin=leftMargin-90;

for i=1:size(Node,1)
   % Positioning
    
    left_corner=[leftMargin,(topMargin + (i-1) * tagSpacing)];
    
   % add output tag for Node parameters
    out_name=sprintf('%s/Cell%d',Heart,i);
    add_block('simulink/Signal Routing/From',out_name);
    x0=left_corner(1);
    y0=left_corner(2)+10;
    set_param(out_name,'Position',[x0 y0 x0+tagl y0+tagw]);
    set_param(out_name,'GotoTag',sprintf('Cell_%d',i));
    set_param(out_name,'ShowName','off');
    add_line(Heart,sprintf('Cell%d/1',i),sprintf('Cell_out/%d',i));
       
end
for i=1:size(Path_name,1)
   % Positioning
    left_corner=[leftMargin,(topMargin + (size(Node,1)+i) * tagSpacing)];
    
   % add output tag for Path parameters
    out_name=sprintf('%s/EGM%d',Heart,i);
    add_block('simulink/Signal Routing/From',out_name);
    x0=left_corner(1);
    y0=left_corner(2)+10;
    set_param(out_name,'Position',[x0 y0 x0+tagl y0+tagw]);
    set_param(out_name,'GotoTag',sprintf('EGM_%d',i));
    set_param(out_name,'ShowName','off');
    add_line(Heart,sprintf('EGM%d/1',i),sprintf('EGM_out/%d',i));
end 

for i=1:size(Path_name,1)
   % Positioning
    left_corner=[leftMargin,(topMargin + (size(Node,1)+size(Path_name,1)+i+1) * tagSpacing)];
    
   % add output tag for Node parameters
    out_name=sprintf('%s/Wave%d',Heart,i);
    add_block('simulink/Signal Routing/From',out_name);
    x0=left_corner(1);
    y0=left_corner(2)+10;
    set_param(out_name,'Position',[x0 y0 x0+tagl y0+tagw]);
    set_param(out_name,'GotoTag',sprintf('wave_%d',i));
    set_param(out_name,'ShowName','off');
    add_line(Heart,sprintf('Wave%d/1',i),sprintf('Wave_out/%d',i));
end
save_system(HeartModel, [systempath,filesep,HeartModel]);

bdclose('all'); %closes any open Simulink windows

end
