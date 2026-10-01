% Define the plot function using the data and plot properties
function plotExp(chartProperty,figFilename)
    % Create a new figure
    figure;
    if isfield(chartProperty,'tiledlayout')
        % check if tiledlayout is an array
        if isnumeric(chartProperty.tiledlayout)
            % Create a tiled layout with the specified number of rows and columns
            t=tiledlayout(chartProperty.tiledlayout(1), chartProperty.tiledlayout(2));
        else
            % Create a tiled layout with the default number of rows and columns
            t=tiledlayout(chartProperty.tiledlayout);
        end
    end
    % Extract the plot properties from the chartProperty struct
    plotProperties = chartProperty.plotProperties;
    % Plot the data
    for i = 1:numel(plotProperties)
        plotProperty = plotProperties(i);
        % Create a subplot with the specified properties
        if isfield(plotProperty,'span')
            ax=nexttile([plotProperty.span(1),plotProperty.span(2)]);
        else
            ax=nexttile;
        end
        hold(ax, 'on');
        lines_N=numel(plotProperty.data);
        fit_num=0;
        lines=[];
        for j = 1:numel(plotProperty.data)
            dataProperty = plotProperty.data(j);
            xdata=dataProperty.x;
            ydata=dataProperty.y;
            % Extract the other properties of dataProperty and add them to the LineSpec struct 
            Linespect=struct();
            properties_name=fieldnames(dataProperty);            
            for k = 1:numel(properties_name)   
                if ~(strcmp(properties_name{k}, 'x')) && ~(strcmp(properties_name{k}, 'y'))
                    if ~(strcmp(properties_name{k}, 'fit'))
                        Linespect.(properties_name{k})=dataProperty.(properties_name{k});                        
                    end
                end
            end
            if numel(fieldnames(Linespect)) >0                
                l=plot(ax, xdata, ydata,Linespect);
                lines=[lines,l];
            else
                l=plot(ax, xdata, ydata);
                lines=[lines,l];
            end
            if any (strcmp(properties_name, 'fit'))
                [curve_fit,~]= fit(xdata,ydata, dataProperty.fit,'Normalize','on');
                fit_num=fit_num+1;
                if isfield(Linespect,'Color')
                    l=plot(ax,xdata, curve_fit(xdata),"Color",Linespect.Color);
                    lines=[lines,l];
                else
                    l=plot(ax,xdata, curve_fit(xdata));
                    lines=[lines,l];
                end
            end         
            
        end
        hold(ax, 'off');
        if isfield(plotProperty, 'xLim')
            xlim(ax, plotProperty.xLim);
        end
        if isfield(plotProperty, 'yLim')
            ylim(ax, plotProperty.yLim);
        end
        if isfield(plotProperty,'xLabel')
            xlabel(ax, plotProperty.xLabel);
        end
        if isfield(plotProperty,'yLabel')
            if isfield(plotProperty,'Rotation')
                y=ylabel(ax, plotProperty.yLabel,'Rotation',plotProperty.Rotation,'VerticalAlignment','middle');
                set(y, 'Units', 'Normalized', 'Position', [-0.1, 0.5])
            else
                ylabel(ax, plotProperty.yLabel);
            end
        end
        if isfield(plotProperty, 'grid')
            grid(ax, plotProperty.grid);
        end
        if ~isfield(plotProperty, 'xticklabels')
            xticklabels(ax,{})
        end
        if isfield(plotProperty,'title')
            title(ax, plotProperty.title);
        end
        if isfield(plotProperty,'box')
            box(ax, plotProperty.box)
        end
        if isfield(plotProperty, 'legend')
            labels=plotProperty.legend.labels;
            if isfield(plotProperty, 'legend_order')
                legend_order=lines(plotProperty.legend_order);
                
                lgd=legend(ax,  legend_order, labels);
            else
                lgd=legend(ax, labels);
            end
            
            
            % Set legend properties based on the legend property struct
            if isfield(plotProperty.legend, 'Location')
                set(lgd, 'Location', plotProperty.legend.Location);
            end
            if isfield(plotProperty.legend, 'NumColumns')
                set(lgd, 'NumColumns', plotProperty.legend.NumColumns);
            end
        end

    end
    xticklabels(ax,'auto')
    chart_properties_name=fieldnames(chartProperty); 
    for k = 1:numel(chart_properties_name) 
        if ~(strcmp(chart_properties_name{k}, 'tiledlayout')) && ~(strcmp(chart_properties_name{k}, 'plotProperties'))
           if strcmp(chart_properties_name{k}, 'Title') || strcmp(chart_properties_name{k}, 'XLabel') ||strcmp(chart_properties_name{k}, 'YLabel')  
                t.(chart_properties_name{k}).String =chartProperty.(chart_properties_name{k});
           else
               t.(chart_properties_name{k})=chartProperty.(chart_properties_name{k});
           end
        end
    end
    % Save the figure to png and eps files
    saveas(gcf, [figFilename,'.png']);
    saveas(gcf, [figFilename,'.eps'],'epsc');
    saveas(gcf, [figFilename,'.fig']);
end



% 
% data_1= struct('x', data.xvar, 'y', data1.yvar, 'lineStyle', '--', 'marker', 'o', 'markerSize', 10);
% 
% subplot_1= struct( 'title', 'Title', 'xLabel', 'X-axis Label', 'yLabel', 'Y-axis Label', 'xLim', [], 'yLim', [])
% 
% % Construct a plot property struct for ax without the data for setPlotProperties
% plotProperty = struct('subplot', [1, 1, 1],  'property',subplot_1,'data', [data_1]);
% 
% plotProperties = [plotProperty];





