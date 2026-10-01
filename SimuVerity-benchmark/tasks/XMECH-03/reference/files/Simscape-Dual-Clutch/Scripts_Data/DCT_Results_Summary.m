% SCRIPT TO LOAD ALL RESULTS FILES AND PRINT SUMMARY TO AN EXCEL FILE
% Copyright 2011-2025 The MathWorks, Inc.

clear DCT_Table_Summary

DCTData_File_List = dir('DCTRES*.mat');
for i = 1:length(DCTData_File_List)
    load(DCTData_File_List(i).name);
    data=eval(char(DCTData_File_List(i).name(1:end-4)));
    DCT_Table_Summary(i,:) = {char(DCTData_File_List(i).name(1:end-4)) num2str(data.Fuel_Used_Liters) num2str(data.Elapsed_Sim_Time)};
    clear DCTRES*
    clear data
end
xlswrite('DCT_Results_Summary.xls',DCT_Table_Summary,'ResultsSheet','A2');

    
