function [ptcld, extr_data] = stem_params(len,rmax,rmin,varargin)
%stem_params Produce point cloud and extrusion data for hourglass-shaped stem
%   [ptcld, extr_data] = stem_params(len,rmax,rmin,varargin)
%
%   You can specify:
%       len    stem length
%       rmax   maximum radius (at ends)
%       rmin   minimum radius (at middle)
%
%   Point cloud data will be centered at [0,0,0]
%
% Copyright 2021-2026 The MathWorks, Inc.

% Parameters for stem
if (nargin == 0)
    len  = 0.4;
    rmax = 0.1;
    rmin = 0.03;
    showplot = 'plot';
end

% Check if plot should be produced
if (isempty(varargin))
    showplot = 'n';
else
    showplot = varargin;
end

% Point cloud
npts_len  = 10;
npts_cir  = 20;

t = linspace(0,2*pi,npts_len);
r = rmin + (cos(t)+1)*(rmax-rmin)/2;
[X,Y,Z] = cylinder(r);
Z = (Z-0.5)*len;

ptcld=unique([reshape(X,[],1) reshape(Y,[],1) reshape(Z,[],1)],'rows');

% Extrusion
t_extr = linspace(0,2*pi,npts_len*3)';
r_extr = rmin + (cos(t_extr)+1)/2*(rmax-rmin);
x_extr = [0;r_extr;0];
y_extr = [-0.5;linspace(-0.5,0.5,length(r_extr))';0.5]*len;
extr_data = [x_extr y_extr];

% Plot diagram to show parameters and extrusion
if (nargin == 0 || strcmpi(showplot,'plot'))
    
    % Figure name
    figString = ['h1_' mfilename];
    % Only create a figure if no figure exists
    figExist = 0;
    fig_hExist = evalin('base',['exist(''' figString ''')']);
    if (fig_hExist)
        figExist = evalin('base',['ishandle(' figString ') && strcmp(get(' figString ', ''type''), ''figure'')']);
    end
    if ~figExist
        fig_h = figure('Name',figString);
        assignin('base',figString,fig_h);
    else
        fig_h = evalin('base',figString);
    end
    figure(fig_h)
    clf(fig_h)
    
    temp_colororder = get(gca,'defaultAxesColorOrder');
    
    %plot3(ptcld(:,1),ptcld(:,2),ptcld(:,3),'o','MarkerFaceColor',temp_colororder(2,:))
    surf(X,Y,Z,'Marker','o','MarkerFaceColor',temp_colororder(2,:),'FaceColor',[0.6 0.6 0.9],'EdgeColor',[0.6 0.6 0.9],'FaceAlpha',0.3)
    axis equal
    hold on
    
    plot3([0 0],[0 -rmin],[0 0],'b-d','MarkerFaceColor','b','LineWidth',1)
    text(0,-rmin*1.5,0,'rmin','Color','blue')
    plot3([0 rmax],[0 0],[len/2 len/2],'r-d','MarkerFaceColor','r','LineWidth',1)
    text(rmax*0.75,0,len/2,'rmax','Color','red')
    plot3([-rmax -rmax],[-rmax -rmax],[-len/2 len/2],'c-d','MarkerFaceColor','c','LineWidth',1)
    text(-rmax,-rmax,0,'len','Color','cyan')
    
    title(['[ptcld, extr\_data] = stem\_params(len, rmax, rmin)']);
    hold off
    box on
    axis equal
    grid off
end