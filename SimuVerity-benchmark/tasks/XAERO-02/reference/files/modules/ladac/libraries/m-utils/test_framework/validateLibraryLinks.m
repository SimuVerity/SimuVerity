function [unresolved_links] = validateLibraryLinks(parent_dir, verbose)
% validateLibraryLinks checks all simulink files for valid library links
%   The function converts parses through all files in the specified parent
%   directory and in all subfolders. It opens every .slx file and checks
%   that all library links are valid and can be resolved. 
%
% Syntax:
%   validateLibraryLinks( parent_dir, do_test_run )
%
% Inputs:
%   parent_dir          full path to the parent directory
%
%   verbose             if true, print detailed information of progress
%
% Outputs:
%   unresolved_links    list of all models and libraries with unresolved
%                       library links and their names
%

% Disclaimer:
%   Copyright (C) 2022 Fabian Guecker
%   Copyright (C) 2022 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

index_file = 1;
unresolved_links = {};

filelist = dir( fullfile( parent_dir, ['**/*.slx'] ));

num_files = length(filelist);
slxfilelist = cell(num_files, 1);

bdclose('all');

for i = 1:num_files
    slxfilelist{i} = [ filelist(i).folder, '/', filelist(i).name ];
end

size_slxfilelist = size(slxfilelist, 1);

for i=1:size(slxfilelist, 1)
 
    slxfilename = slxfilelist{i};
    
    is_all_resolved = true;
    load_system( slxfilename );
    
    info_struct = libinfo(gcs);
    
    index_unresolved = 2;
    for j = 1:length(info_struct)
        if strcmp( info_struct(j).LinkStatus, 'unresolved' )
            is_all_resolved = false;
            
            unresolved_links{index_file, index_unresolved} = ...
                info_struct(j).Library;
            index_unresolved = index_unresolved + 1;
        end
    end

    if(verbose)
        disp([num2str(i), ' / ', num2str(size_slxfilelist), ' ', slxfilelist{i}]);
    end
    
    if ~is_all_resolved
        if(verbose)
            disp(['Unresolved library links in: ',slxfilename])
        end
        
        unresolved_links{index_file, 1} = slxfilelist{i};
        index_file = index_file + 1;
    end
    
    close_system( slxfilename, 0);
    
end

end


