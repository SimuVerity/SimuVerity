function [extr_data_top, extr_data_top_upper, extr_data_top_lower] = sm_spinning_top_totem_param(varargin)

%% Assign default values
if (nargin==0)
    showplot = 'plot';
else
    showplot = varargin(end);
end

% Global size parameters
L = 29; W = L; H = 36;
R = 2;  % radius
th = R; % thickness
topHeight    = 2/3*H - th/2;
bottomHeight = 1/3*H - th/2;

%% Half Top Circle
theta = linspace(0, pi/2, 30)';
x1 = R*cos(theta);
y1 = R*sin(theta) + H - R;

%% Decay
xI = [R;1.3*R; L/2];
yI = [H-R;1.85*(bottomHeight+th);bottomHeight+th];

ft = fittype( 'a./log(b*x)+c', 'independent', 'x', 'dependent', 'y' );

opts = fitoptions( 'Method', 'NonlinearLeastSquares' );
opts.Display = 'Off';
opts.Lower = [0 0 0];
opts.StartPoint = [0.678735154857773 0.757740130578333 0.743132468124916];

fitresult = fit( xI, yI, ft, opts );

x2 = flip(linspace(R, L/2, 50)');
y2 = feval(fitresult, x2);


%% Line
x3 = [L/2 L/2]';
y3 = [bottomHeight bottomHeight+th]';

%% Gaussian
xG = [-L/2; -L/16; 0; L/16; L/2];
yG = [0; bottomHeight-L/16; bottomHeight; bottomHeight-L/16; 0];

ft = fittype( 'gauss1' );

opts2 = fitoptions( 'Method', 'NonlinearLeastSquares' );
opts2.Lower      = [-Inf -Inf 0];
opts2.StartPoint = [11 0 1];

fitresult = fit( xG, yG, ft, opts2 );

x4 = linspace(0, L/2, 60)';
y4 = -feval(fitresult, x4) + bottomHeight;


%% Generate Matrix
x = [x4; x3; x2(2:end-1); x1];
y = [y4; y3; y2(2:end-1); y1];
extr_data_top = [x y]/6;

%% Separate lowest part into separate extrusion
top_lower_ind = find(y<5,1,'last');
extr_data_top_lower = [extr_data_top(1:top_lower_ind,:); 0 extr_data_top(top_lower_ind,2)];
extr_data_top_upper = [0 extr_data_top(top_lower_ind,2); extr_data_top(top_lower_ind:end,:); 0 extr_data_top(end,end)];

%%
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
    subplot(1,2,1)
    plot(x1, y1, "*-");
    axis equal;
    %axis([0 L/2 -5 H]);
    hold on
    plot(x2, y2, "*-")
    plot(x4, y4, "*-")
    plot(x3, y3, "*-")
    hold off

    subplot(1,2,2)
    plot(extr_data_top_lower(:,1)*6,extr_data_top_lower(:,2)*6,'-x')
    axis equal
    %axis([0 L/2 -5 H]);
    hold on
    plot(extr_data_top_upper(:,1)*6,extr_data_top_upper(:,2)*6,'-o')
    hold off
end

%% Additional commands - used to set up example

%% Save results
%save sm_spinning_top_totem_extr_data.mat extr_data_top extr_data_top_lower extr_data_top_upper;

%% Create convex hull stl
% sm_revolution_to_stl(extr_data_top,'top_totem_complete_convex_hull.stl')