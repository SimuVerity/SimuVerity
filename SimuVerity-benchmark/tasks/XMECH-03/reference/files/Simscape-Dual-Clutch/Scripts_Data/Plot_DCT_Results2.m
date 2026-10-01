% SCRIPT TO OVERLAY TWO RUNS OF Dual_Clutch_Trans
% Copyright 2011-2025 The MathWorks, Inc.
PlotStyles = {'b-' 'r--'};
LineWidths = [5 2];

%PlotData_Basename = {'DCTRES_Abs_Sim_Des' 'DCTRES_Abs_Sim_Rea'};
PlotData_Basename = who('DCTRES*');

disp(['PLOTTING RESULTS FROM DRIVE CYCLE ' num2str(Drive_Cycle_Num)]);
disp(' ');

Res_Names = setdiff(fieldnames(eval(PlotData_Basename{1})),'Elapsed_Sim_Time');
Res_Names = setdiff(Res_Names,'Fuel_Used_Liters');
for ds_i = 1:2%length(PlotData_Basename)
    PlotData = char(PlotData_Basename{ds_i});
    for i = 1:length(Res_Names)
        %disp(['CREATING FIGURE ' num2str(i)]);
        figure(i)
        num_signals = length(eval([PlotData '.' char(Res_Names{i}) '.signals']));
        for j=1:num_signals
            %disp(['...CREATING SUBPLOT ' num2str(j) ' with ' num2str(num_signals) ' signals.']);
            subplot(num_signals,1,j);
            y_data = eval([PlotData '.' char(Res_Names{i}) '.signals(' num2str(j) ').values;']);
            time_vector = eval([PlotData '.' char(Res_Names{i}) '.time;']);
            signal_name = eval([PlotData '.' char(Res_Names{i}) '.signals(' num2str(j) ').label;']);
            plot(time_vector,y_data,char(PlotStyles{ds_i}),'LineWidth',LineWidths(ds_i));
            %disp(signal_name)
            title([signal_name ', Drive Cycle ' num2str(Drive_Cycle_Num)]);
            hold on
        end
        if(ds_i == length(PlotData_Basename))
        %if(ds_i == 1)
            legend(strrep(PlotData_Basename,'_',' '),'Location','Best');
            text('String',[strrep(char(PlotData_Basename{1}),'_',' '), ', ' num2str(eval([char(PlotData_Basename{1}) '.Elapsed_Sim_Time'])) ', ' num2str(eval([char(PlotData_Basename{1}) '.Fuel_Used_Liters']))],'Units','normalized','Position',[0.01 0.12]);
            text('String',[strrep(char(PlotData_Basename{2}),'_',' '), ', ' num2str(eval([char(PlotData_Basename{2}) '.Elapsed_Sim_Time'])) ', ' num2str(eval([char(PlotData_Basename{2}) '.Fuel_Used_Liters']))],'Units','normalized','Position',[0.01 0.08]);
            text('String',[datestr(now) ' ' version],'Units','normalized','Position',[0.01 0.04]);
            %saveas(gcf,['./Figures/DCT_Compare_DC' num2str(Drive_Cycle_Num) '_' char(Res_Names{i})],'fig');
        end
    end
end
%close all
