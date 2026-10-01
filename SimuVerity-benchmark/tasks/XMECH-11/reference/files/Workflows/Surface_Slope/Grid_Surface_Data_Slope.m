function gs_data = Grid_Surface_Data_Slope(x, y, slope_x, slope_z, slope_x0, x_res, varargin)

% Default data to show diagram
if(nargin==0)
    x         = 25;
    y         = 5;
    slope_x   = 15;
    slope_z   = 3;
    slope_x0  = 5;
    x_res     = 0.2;
end

% Check if plot should be produced
if (isempty(varargin))
    showplot = 'n';
else
    showplot = char(varargin);
end
slope_fin = slope_x0+slope_x;

% Assemble x points
xg = [-5 slope_x0:x_res:slope_fin x];

% Assemble y points
yg = [0 y]-y/2;

% Assemble heights
z_vec = smoothstep(xg,slope_x0,slope_fin,slope_z);

% Create matrix
zg = repmat(z_vec',1,length(yg));

% Add to output structure
gs_data.xg = xg;
gs_data.yg = yg;
gs_data.zg = zg;


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

    [X,Y] = meshgrid(xg, yg);
    surf(X',Y',zg);
    axis equal
    box on
    xlabel('x (m)')
    ylabel('y (m)')
    zlabel('z (m)')
    title('[gs] = Grid\_Surface\_Data\_Slope(x, y, slope\_x, slope\_z, slope\_x0, x\_res);');
end


    function [y] = smoothstep(x,sta,fin,hei)
    % Creates smooth step from start to finish
        y = zeros(size(x));
        for i = 1:length(x)
            if(x(i)<sta), y(i)=0;
            elseif (x(i)>fin), y(i)=1;
            else
                x_cla = (x(i)-sta)/(fin-sta);            
                y(i)  = x_cla * x_cla * (3 - 2 * x_cla);
            end
        end
        y = y*hei;
    end
end