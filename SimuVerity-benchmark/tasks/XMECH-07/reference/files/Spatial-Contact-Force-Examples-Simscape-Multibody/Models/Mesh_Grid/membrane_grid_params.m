function [grid_x, grid_y, grid_h] = membrane_grid_params(K,scale_xyz,varargin)
% Generate grid surface points from L-shaped membrane eigenfunctions.
%
% Copyright 2021-2026 The MathWorks, Inc.

% Default data to show diagram
if (nargin == 0)
    K=1;
    scale_xyz = [1 1 1];
    showplot = 'plot';
end

% Check if plot should be produced
if (isempty(varargin))
    showplot = 'n';
else
    showplot = varargin;
end

grid_h = membrane(K)*scale_xyz(3);
grid_x = linspace(-1,1,size(grid_h,1))*scale_xyz(1);
grid_y = linspace(-1,1,size(grid_h,2))*scale_xyz(2);

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
    
    %temp_colororder = get(gca,'defaultAxesColorOrder');
    
    surf(grid_x, grid_y, grid_h,'LineWidth',0.01,'EdgeColor',[0.6 0.6 0.6])
    box on
    
    title(['[grid\_x, grid\_y, grid\_h]  = membrane\_grid\_params(K, scale\_xyz);']);
    hold off
    box on
    axis equal
    grid off
end