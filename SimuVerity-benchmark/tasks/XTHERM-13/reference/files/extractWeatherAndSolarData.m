% This function returns a monthly averaged table of hourly input data namely "Ambient Temperature(degC)" and "Total Solar Irradiation(W/m^2)", 
% in "Month" "Avg Temperature(degC)", "Average Total Solar Irradiation(W/m^2)" format.

% Copyright 2023 - 2024 The MathWorks, Inc.

function avgTable= extractWeatherAndSolarData(hrlyData)
    months = categorical(["Jan";"Feb";"Mar";"Apr";"May";"Jun";"Jul";"Aug";"Sep";"Oct";"Nov";"Dec"]); % Define categorical variables months 
    months = reordercats(months,["Jan";"Feb";"Mar";"Apr";"May";"Jun";"Jul";"Aug";"Sep";"Oct";"Nov";"Dec"]); % Set the order for categorical variables months
    winSize = floor(length(hrlyData.hourlyData.("Time(hrs)"))/12); % Define averaging window size 
    resizedTemp = transpose(hrlyData.hourlyData.("Ambient Temperature(degC)")(1:12*winSize,:));  % Read column from the input table in to vector of correct size
    resizedIrradiance = transpose(hrlyData.hourlyData.("Total Solar Irradiation(W/m^2)")(1:12*winSize,:)); % Read column from the input table in to vector of correct size
    resizedTemp = reshape(resizedTemp,[winSize 12]); % Reshape the Vector into matrix with 12 columns representing 12 months of the year   
    resizedIrradiance = reshape(resizedIrradiance,[winSize 12]); % Reshape the Vector into matrix with 12 columns representing 12 months of the year
    mthAvgTemp = mean(resizedTemp); % Calculate monthly average by calculating the mean of each of the column
    mthAvgIrradiance = mean(resizedIrradiance);
    avgTable = table(months,transpose(mthAvgTemp),transpose(mthAvgIrradiance),'VariableNames',{'Month','Avg Temperature(degC)','Average Total Solar Irradiation(W/m^2)'});
end

