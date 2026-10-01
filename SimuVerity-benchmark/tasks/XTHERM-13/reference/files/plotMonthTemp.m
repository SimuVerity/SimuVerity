% This function plots monthly averaged temperature against months of the
% year

% Copyright 2023 - 2024 The MathWorks, Inc.

function plotMonthTemp(tempTbl)
    months = categorical(["Jan";"Feb";"Mar";"Apr";"May";"Jun";"Jul";"Aug";"Sep";"Oct";"Nov";"Dec"]); % Define categorical variables months 
    months = reordercats(months,["Jan";"Feb";"Mar";"Apr";"May";"Jun";"Jul";"Aug";"Sep";"Oct";"Nov";"Dec"]);% Set the order for categorical variables months
    figure("Name","Ambient T");
    plot(months,tempTbl.("Avg Temperature(degC)"),'Color','green',LineWidth=1.5);
    title('Monthly Average Temperature');
    ylabel('Temperature (degC)');
end

