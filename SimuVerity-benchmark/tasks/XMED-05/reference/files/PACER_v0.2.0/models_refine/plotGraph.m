figure;
modelcfg='N3Cfg_second_93N270P61VM_EGM.mat';
figFilename='93N270P61VM_newProbe';
dim=load(modelcfg);
num_Node=size(dim.Node,1);
c=zeros(num_Node, 3);
for n=1:size(dim.Node,1) %iterates through node list
    % Which type of node
    if strcmp(dim.Node_name{n,2},'N')
        c(n,:)=[1 0 0];
    else if strcmp(dim.Node_name{n,2},'NM')
            c(n,:)=[1 1 0];
    else if strcmp(dim.Node_name{n,2},'M')
            c(n,:)=[0 0 1];
    else
        error('The dimension of Nodecfg does not match');
    end
    end
    end
end
node_s=scatter(dim.Node_pos(:,1),dim.Node_pos(:,2),[],c,'filled','MarkerEdgeColor','k');
hold on;
% for n=1:length(dim.Node_pos(:,1))
%     text(dim.Node_pos(n,1),dim.Node_pos(n,2)+2,int2str(n),'Color','blue','FontSize',12);
% end
% path
path_plot=[];
for n=1:size(dim.Path,1)
    nodei_x=dim.Node_pos(dim.Path(n,1),1);
    nodej_x=dim.Node_pos(dim.Path(n,2),1);
    nodei_y=dim.Node_pos(dim.Path(n,1),2);
    nodej_y=dim.Node_pos(dim.Path(n,2),2);
    sc=[];
    if ~isempty(strfind(dim.Node_name{dim.Path(n,1),2},'N')) && ~isempty(strfind(dim.Node_name{dim.Path(n,2),2},'N'))
        sc=[1 0 0];
    elseif ~isempty(strfind(dim.Node_name{dim.Path(n,1),2},'N')) || ~isempty(strfind(dim.Node_name{dim.Path(n,2),2},'N'))
        sc=[0 1 0];
    elseif ~isempty(strfind(dim.Node_name{dim.Path(n,1),2},'M')) && ~isempty(strfind(dim.Node_name{dim.Path(n,2),2},'M'))
        sc=[0 0 0];
    else 
        fprint('should not be here')
    end

    path_plot(n)=line([nodei_x,nodej_x],[nodei_y,nodej_y],'LineWidth',1.5,'Color',sc);
    line_midx=(nodei_x+nodej_x)/2;
    line_midy=(nodei_y+nodej_y)/2;
    text(line_midx,line_midy,[int2str(n)],'Color','blue','FontSize',12);
end

probe_s=scatter(dim.Probe_pos(:,1),dim.Probe_pos(:,2),[],'r','filled','Marker','diamond');

saveas(gcf, [figFilename,'.fig']);