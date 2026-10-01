%% Code to make all parts transparent except lift, tilt, and steer hydraulic cylinders
% To reset to original values, run startup script

% Copyright 2023-2025 The MathWorks, Inc.

% Find number of body groups in Wheel_Loader structure
sizeBG = length(Wheel_Loader.bodyGroups);

% Body groups for hydraulic cylinders
BGarrayOpaqueBG.cyl = [50 51 6 7 8 9 4 5];
BGarrayOpaqueBG.lcy = [6 7 8 9 4 5];
BGarrayOpaqueBG.scy = [50 51];
BGarrayOpaqueBG.drv = [76 73 43 64 42 48 71 49 38 40 41 39 44 72 62 63 45 65 47 46 57 56 58 59 66 60 61 67];
BGarrayOpaqueBG.cvt = [63];
BGarrayOpaqueBG.eng = [999]; % All transparent except extras
BGarrayOpaqueBG.tir = [25 33 24 32 27 35 26 34];
BGarrayOpaqueBG.bkl = [999];
BGarrayOpaqueBG.grl = [10 11 12 13 14 15 16 53];
BGarrayOpaqueBG.lnk = [2 3 17 18 19 53 6 7 8 9 4 5];

opc_trans = 0.05;

% Loop over body groups
for bg_i = 1:sizeBG

    % Find number of subgroups
    sizeSG = length(Wheel_Loader.bodyGroups(bg_i).subGroups);

    % If (not a cylinder)
    if(~ismember(bg_i,BGarrayOpaqueBG.cyl))
        % Loop over subgroups
        for sg_i = 1:sizeSG
            % Set transparency to 0.1
            Wheel_Loader.bodyGroups(bg_i).subGroups(sg_i).visualProperties.opacity = opc_trans;
        end
    end
end

% For parts with custom variables for transparency
HMPST.Vis.RAxleHou.opc   = opc_trans;
HMPST.Vis.FAxleHou.opc   = opc_trans;
HMPST.Vis.RDiffHou.opc   = opc_trans;
HMPST.Vis.FDiffHou.opc   = opc_trans; 
HMPST.Vis.TfrGearHou.opc = opc_trans;  % Leave opaque for cvt
HMPST.Vis.FDriveHou.opc  = opc_trans;
HMPST.Vis.WhlPlaHou.opc  = opc_trans;
HMPST.Vis.SteerWheel.opc = opc_trans;  % Leave opaque for steering
HMPST.Vis.SeatTrim.opc   = opc_trans;
HMPST.Vis.Bucket.opc     = opc_trans; % Leave opaque for bucket load
HMPST.Vis.Cap.opc        = opc_trans;
HMPST.Vis.Light.opc      = opc_trans;
HMPST.Vis.Lens.opc       = opc_trans;
HMPST.Vis.Eng.opc        = opc_trans;


