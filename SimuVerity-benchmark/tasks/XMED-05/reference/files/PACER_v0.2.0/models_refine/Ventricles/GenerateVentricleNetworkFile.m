% This script generates triangular meshes of a ventricular myocardium using 
% a binary mask image. The outside contour of the binary mask gives a
% sequence of points that can be used as in input to triangle, an
% application that generates quality triangular meshes.
clear all;

PixelDim = 0.07; % units of original network - not sure about units

% Load in mask image and do some processing
I = imread('Ventricles.png');
I = ~logical(I);
Ip = I;
Ip = padarray(Ip,[10,10],0,'both');
Ip = single(Ip); 
Ip = imresize(Ip,2); PixelDim = 0.07/2;
Ip = imgaussfilt(Ip,10);

% Parameters - StepSize is for sampling around the edge closed contour and
% MaxArea is for target maximum triangle size
%StepSize = 50; MaxArea = 4; % finest mesh
%StepSize = 100; MaxArea = 12;
%StepSize = 150; MaxArea = 16;
%StepSize = 302; MaxArea = 32;
StepSize = 601; MaxArea = 64; % coarsest mesh

% find mask boundaries using contours - alternative is to use e.g.
% bwboundaries - possible advantages to contour is that the edges of the
% scars will be smoothed a little.
[X,Y]=ndgrid(1:size(Ip,2),1:size(Ip,1));
X = X'*PixelDim; Y=Y'*PixelDim; %Ip = flipud(Ip);
[C,H]=contour(X,Y,double(Ip),[0.99,0.99]);

% Find indices for each contour - contours are all closed, so modify 
% indices so that the last one in each contour is the same as the
% first,i.e. do not include the last index.
Contours = {};
IdxStart = 2;
IdxContour = 1;
while IdxStart < size(C,2),
    Contours{IdxContour} = [IdxStart:StepSize:IdxStart+C(2,IdxStart-1)-2];
    IdxStart = IdxStart+C(2,IdxStart-1)+1;
    IdxContour = IdxContour+1;
end;

% Indices of contour points
CContourIdx = cat(2,Contours{:});

% Unique vertices
Vertices = C(:,CContourIdx);
MaxY = max(Vertices(2,:));
Vertices(2,:) = MaxY - Vertices(2,:);

% Convert pixel dimensions into actual dimensions
MinX = min(Vertices(1,:));
MinY = min(Vertices(2,:));
Vertices(1,:) = (Vertices(1,:)-MinX);
Vertices(2,:) = (Vertices(2,:)-MinY);

% Segments - close the contour between last link and first. Extra indices
% in contours have to be accounted for. For the first contour there is only
% one extra vertex, but in subsequent ones there are two.
VStart = 1;
Segments = [];
for s=1:length(Contours),
    NContour = length(Contours{s});
    LSegments = [VStart:VStart+NContour-2,VStart+NContour-1;...
                 VStart+1:VStart+NContour-1,VStart];
    Segments = [Segments,LSegments];
    VStart = VStart+NContour;%+1;
end;

% open and write poly file
fid = fopen(sprintf('VentricleCrossSectionPSLG_%1d.poly',StepSize),'w');
fprintf(fid,'%d 2 0 1\n',size(Vertices,2));
fprintf(fid,'%d %f %f 1\n',[1:size(Vertices,2);Vertices]);
fprintf(fid,'%d 1\n',size(Segments,2));
fprintf(fid,'%d %d %d 1\n',[1:size(Segments,2);Segments]);
fprintf(fid,'%d\n',0);
fclose(fid);

% generate triangular mesh e.g. using triangle -pqa0.25 VentricleCrossSectionPSLG.poly
% ./triangle -rpqu VentricleCrossSectionPSLG.1.poly
% refine triangular mesh e.g. using 
system(sprintf('./triangle -pqa%d VentricleCrossSectionPSLG_%d.poly',MaxArea,StepSize));

% Open and read generated triangles
lines = readlines(sprintf('VentricleCrossSectionPSLG_%d.1.node',StepSize));
trix = zeros(length(lines)-3,1);
triy = zeros(length(lines)-3,1);
for i=2:length(lines)-2
    data = str2num(lines(i));
    trix(i-1) = data(2);
    triy(i-1) = data(3);
end

lines = readlines(sprintf('VentricleCrossSectionPSLG_%d.1.ele',StepSize));
tri = zeros(length(lines)-3,3);
for i=2:length(lines)-2
    data = str2num(lines(i));
    tri(i-1,1:3) = data(2:4);
end


% Shift into the heart network space - these shifts were manually found to
% ensure the ventricular higher density network is consistent with the existing 
% fast conduction network
trix = trix + 67;
triy = triy + 31; 

% Calculate some possibly useful measurements
areas = polyarea(trix(tri),triy(tri),2); % triangle areas
dy=diff([triy(tri),triy(tri(:,1))],1,2);
dx=diff([trix(tri),trix(tri(:,1))],1,2);
edgelengths = sqrt(dx.^2+dy.^2); 
edgelengths = reshape(edgelengths,[prod(size(edgelengths)),1]);

% Load in the fully abstracted heart network.
HN = load('HeartNetwork.txt');

% Original fast conduction network link nodes - fully abstracted
FCNLN = [25,28,26,33,34,38,39];

% Find nearest trix,triy points for the FCN to link to
FCNLNtoVM = [];
for i=1:length(FCNLN)
    Delta = sqrt(sum([trix-HN(FCNLN(i),1),triy-HN(FCNLN(i),2)].^2,2));
    [md,minidx] = min(Delta);
    FCNLNtoVM = [FCNLNtoVM;32+minidx];
end

% Display
RedNodes = [1,9,12];
OrangeNodes = [5,7,8,10,11,15,19:28,33,34,38,39];
BlueNodes = [2:4,6,13,14,16:18];

% Plot original fast conduction network and atrial myocardium overlaid on
% new ventricular myocardium.
figure(1); clf;
h=trimesh(tri,trix,triy); axis equal; set(h,'Color','k');
hold on; s = scatter(trix,triy,40,[0,136/255,209/255],"filled"); set(s,'MarkerEdgeColor','k'); hold off;
hold on; r=scatter(HN(RedNodes,1),HN(RedNodes,2),40,'r','filled'); set(r,'MarkerEdgeColor','k'); hold off;
hold on; o=scatter(HN(OrangeNodes,1),HN(OrangeNodes,2),40,[245/255,124/255,0],'filled'); set(o,'MarkerEdgeColor','k'); hold off;
hold on; b=scatter(HN(BlueNodes,1),HN(BlueNodes,2),40,[0,136/255,209/255],'filled'); set(b,'MarkerEdgeColor','k'); hold off;
set(gca,'XTickLabel',{},'YTickLabel',{},'XColor',[1,1,1],'YColor',[1,1,1],'Box','off','XTick',[],'YTick',[]);
axis off;
%print(gcf,sprintf('Network_NoDim_%d_%d.png',StepSize,MaxArea),'-dpng','-r600');

return;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
fprintf('...Writing node file ...\n');
% Nodes file
linesNodes = readlines('Heart_N3_second_Node.csv');
% Split string into components. First is label which will be VM# for
% ventricular myocardium and the number.The Index number is index 3.
% The x location of the flattened nodes is index 48 and y is index 49.
fid = fopen(sprintf('Heart_N3_second_AdditionalVentricularMyocyteNodes_%d_%d.csv',StepSize,MaxArea),'w');
fprintf(fid,'%s\n',linesNodes(1:end-17));
% Include endocardial PF network
NodeMapping = [];
NodeComponentStrings = strsplit(linesNodes(end-12),',','CollapseDelimiters',false);
NodeMapping = [NodeMapping;str2num(NodeComponentStrings(3)),29];
NodeComponentStrings(3) = num2str(29);
fprintf(fid,'%s,',NodeComponentStrings);
fprintf(fid,'\n');
NodeComponentStrings = strsplit(linesNodes(end-11),',','CollapseDelimiters',false);
NodeMapping = [NodeMapping;str2num(NodeComponentStrings(3)),30];
NodeComponentStrings(3) = num2str(30);
fprintf(fid,'%s,',NodeComponentStrings);
fprintf(fid,'\n');
NodeComponentStrings = strsplit(linesNodes(end-7),',','CollapseDelimiters',false);
NodeMapping = [NodeMapping;str2num(NodeComponentStrings(3)),31];
NodeComponentStrings(3) = num2str(31);
fprintf(fid,'%s,',NodeComponentStrings);
fprintf(fid,'\n');
NodeComponentStrings = strsplit(linesNodes(end-6),',','CollapseDelimiters',false);
NodeMapping = [NodeMapping;str2num(NodeComponentStrings(3)),32];
NodeComponentStrings(3) = num2str(32);
fprintf(fid,'%s,',NodeComponentStrings);
fprintf(fid,'\n');
% Ventricular myocardium
NodeComponentStrings = strsplit(linesNodes(end-2),',','CollapseDelimiters',false);
IndexVector = [];
for i=1:length(trix)
    NodeComponentStrings(1) = sprintf('VM%d',i);
    NodeComponentStrings(3) = num2str(32+i); IndexVector = [IndexVector;32+i];
    NodeComponentStrings(48) = num2str(trix(i)); % default is 4dp
    NodeComponentStrings(49) = num2str(triy(i));
    fprintf(fid,'%s,',NodeComponentStrings);
    fprintf(fid,'\n');
end
fclose(fid);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
fprintf('...Writing path file ...\n');
% Path file
linesPaths = readlines('Heart_N3_second_Path.csv');
% Split string into components. 
% Update the fast conduction network liks to ventricular myocardium
% Link node 25 (line 33)
PathComponentStrings = strsplit(linesPaths(33),',','CollapseDelimiters',false);
PathComponentStrings(2) = sprintf('VM%d',FCNLNtoVM(1)-32);
HoldEndNode = str2num(PathComponentStrings(3));
PathComponentStrings(4) = num2str(FCNLNtoVM(1));
PathComponentStrings(16) = HN(HoldEndNode,1);
PathComponentStrings(17) = HN(HoldEndNode,2);
PathComponentStrings(18) = trix(FCNLNtoVM(1)-32);
PathComponentStrings(19) = triy(FCNLNtoVM(1)-32);
PathComponentStrings(20) = num2str(sqrt((str2num(PathComponentStrings(16))-str2num(PathComponentStrings(18)))^2 + (str2num(PathComponentStrings(17))-str2num(PathComponentStrings(19)))^2));
linesPaths(33) = strjoin(PathComponentStrings,',');
% Link node 28 (line 34)
PathComponentStrings = strsplit(linesPaths(34),',','CollapseDelimiters',false);
PathComponentStrings(2) = sprintf('VM%d',FCNLNtoVM(2)-32);
HoldEndNode = str2num(PathComponentStrings(3));
PathComponentStrings(4) = num2str(FCNLNtoVM(2));
PathComponentStrings(16) = HN(HoldEndNode,1);
PathComponentStrings(17) = HN(HoldEndNode,2);
PathComponentStrings(18) = trix(FCNLNtoVM(2)-32);
PathComponentStrings(19) = triy(FCNLNtoVM(2)-32);
PathComponentStrings(20) = num2str(sqrt((str2num(PathComponentStrings(16))-str2num(PathComponentStrings(18)))^2 + (str2num(PathComponentStrings(17))-str2num(PathComponentStrings(19)))^2));
linesPaths(34) = strjoin(PathComponentStrings,',');
% Map node 33 (line 36)
PathComponentStrings = strsplit(linesPaths(36),',','CollapseDelimiters',false);
PathComponentStrings(4) = num2str(NodeMapping(1,2));
linesPaths(36) = strjoin(PathComponentStrings,',');
% Map nodes 33 and 34(line 37)
PathComponentStrings = strsplit(linesPaths(37),',','CollapseDelimiters',false);
PathComponentStrings(3) = num2str(NodeMapping(1,2));
PathComponentStrings(4) = num2str(NodeMapping(2,2));
linesPaths(37) = strjoin(PathComponentStrings,',');
% Map node 38 (line 43)
PathComponentStrings = strsplit(linesPaths(43),',','CollapseDelimiters',false);
PathComponentStrings(4) = num2str(NodeMapping(3,2));
linesPaths(43) = strjoin(PathComponentStrings,',');
% Map nodes 38 and 39 (line 44)
PathComponentStrings = strsplit(linesPaths(44),',','CollapseDelimiters',false);
PathComponentStrings(3) = num2str(NodeMapping(3,2));
PathComponentStrings(4) = num2str(NodeMapping(4,2));
linesPaths(44) = strjoin(PathComponentStrings,',');
% Link node 26 (line 45)
PathComponentStrings = strsplit(linesPaths(45),',','CollapseDelimiters',false);
PathComponentStrings(2) = sprintf('VM%d',FCNLNtoVM(3)-32);
HoldEndNode = str2num(PathComponentStrings(3));
PathComponentStrings(4) = num2str(FCNLNtoVM(3));
PathComponentStrings(16) = HN(HoldEndNode,1);
PathComponentStrings(17) = HN(HoldEndNode,2);
PathComponentStrings(18) = trix(FCNLNtoVM(3)-32);
PathComponentStrings(19) = triy(FCNLNtoVM(3)-32);
PathComponentStrings(20) = num2str(sqrt((str2num(PathComponentStrings(16))-str2num(PathComponentStrings(18)))^2 + (str2num(PathComponentStrings(17))-str2num(PathComponentStrings(19)))^2));
linesPaths(45) = strjoin(PathComponentStrings,',');
% Link node 33(29) (line 48)
PathComponentStrings = strsplit(linesPaths(48),',','CollapseDelimiters',false);
PathComponentStrings(2) = sprintf('VM%d',FCNLNtoVM(4)-32);
PathComponentStrings(3) = num2str(NodeMapping(1,2));
PathComponentStrings(4) = num2str(FCNLNtoVM(4));
PathComponentStrings(18) = trix(FCNLNtoVM(4)-32);
PathComponentStrings(19) = triy(FCNLNtoVM(4)-32);
PathComponentStrings(20) = num2str(sqrt((str2num(PathComponentStrings(16))-str2num(PathComponentStrings(18)))^2 + (str2num(PathComponentStrings(17))-str2num(PathComponentStrings(19)))^2));
linesPaths(48) = strjoin(PathComponentStrings,',');
% Link node 34(30) (line 49)
PathComponentStrings = strsplit(linesPaths(49),',','CollapseDelimiters',false);
PathComponentStrings(2) = sprintf('VM%d',FCNLNtoVM(5)-32);
PathComponentStrings(3) = num2str(NodeMapping(2,2));
PathComponentStrings(4) = num2str(FCNLNtoVM(5));
PathComponentStrings(18) = trix(FCNLNtoVM(5)-32);
PathComponentStrings(19) = triy(FCNLNtoVM(5)-32);
PathComponentStrings(20) = num2str(sqrt((str2num(PathComponentStrings(16))-str2num(PathComponentStrings(18)))^2 + (str2num(PathComponentStrings(17))-str2num(PathComponentStrings(19)))^2));
linesPaths(49) = strjoin(PathComponentStrings,',');
% Link node 38(31) (line 50)
PathComponentStrings = strsplit(linesPaths(50),',','CollapseDelimiters',false);
PathComponentStrings(2) = sprintf('VM%d',FCNLNtoVM(6)-32);
PathComponentStrings(3) = num2str(NodeMapping(3,2));
PathComponentStrings(4) = num2str(FCNLNtoVM(6));
PathComponentStrings(18) = trix(FCNLNtoVM(6)-32);
PathComponentStrings(19) = triy(FCNLNtoVM(6)-32);
PathComponentStrings(20) = num2str(sqrt((str2num(PathComponentStrings(16))-str2num(PathComponentStrings(18)))^2 + (str2num(PathComponentStrings(17))-str2num(PathComponentStrings(19)))^2));
linesPaths(50) = strjoin(PathComponentStrings,',');
% Link node 39(32) (line 51)
PathComponentStrings = strsplit(linesPaths(51),',','CollapseDelimiters',false);
PathComponentStrings(2) = sprintf('VM%d',FCNLNtoVM(7)-32);
PathComponentStrings(3) = num2str(NodeMapping(4,2));
PathComponentStrings(4) = num2str(FCNLNtoVM(7));
PathComponentStrings(18) = trix(FCNLNtoVM(7)-32);
PathComponentStrings(19) = triy(FCNLNtoVM(7)-32);
PathComponentStrings(20) = num2str(sqrt((str2num(PathComponentStrings(16))-str2num(PathComponentStrings(18)))^2 + (str2num(PathComponentStrings(17))-str2num(PathComponentStrings(19)))^2));
linesPaths(51) = strjoin(PathComponentStrings,',');

% Ventricular template
TemplateLine = linesPaths(end-1);
TemplateLineStrings = strsplit(TemplateLine,',','CollapseDelimiters',false);

% Remove ventricular myocyte links
ReducedlinesPaths = linesPaths([1:34,36,37,43:45,48:51]);

% Apply node mapping to FCNLN
fid = fopen(sprintf('Heart_N3_second_AdditionalVentricularMyocytePaths_%d_%d.csv',StepSize,MaxArea),'w');
for i=1:length(ReducedlinesPaths)
    fprintf(fid,'%s\n',ReducedlinesPaths(i));
end
Indices = [1,2;2,3;3,1];
for i=1:size(tri,1)
    for j=1:3
        TemplateLineStrings(1) = sprintf('VM%d',tri(i,Indices(j,1)));
        TemplateLineStrings(2) = sprintf('VM%d',tri(i,Indices(j,2)));
        TemplateLineStrings(3) = num2str(tri(i,Indices(j,1))+32);
        TemplateLineStrings(4) = num2str(tri(i,Indices(j,2))+32);

        TemplateLineStrings(16) = trix(tri(i,Indices(j,1)));
        TemplateLineStrings(17) = triy(tri(i,Indices(j,1)));
        TemplateLineStrings(18) = trix(tri(i,Indices(j,2)));
        TemplateLineStrings(19) = triy(tri(i,Indices(j,2)));
        TemplateLineStrings(20) = num2str(sqrt((str2num(TemplateLineStrings(16))-str2num(TemplateLineStrings(18)))^2 + (str2num(TemplateLineStrings(17))-str2num(TemplateLineStrings(19)))^2));
       
        PrintLine = strjoin(TemplateLineStrings,',');
        fprintf(fid,'%s\n',PrintLine);
    end
end
fclose(fid);