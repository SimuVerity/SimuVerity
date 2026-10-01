% This function returns break even years for TES cost 

% Copyright 2023 - 2024 The MathWorks, Inc.

function brkYrs = fitPolyAndSolve(yrs,cstReco)

    cstReco2 = polyfit(transpose(yrs),transpose(cstReco),2);
    polyRoots = roots(cstReco2);
    brkYrs = round(max(polyRoots),3,'significant');
 
end