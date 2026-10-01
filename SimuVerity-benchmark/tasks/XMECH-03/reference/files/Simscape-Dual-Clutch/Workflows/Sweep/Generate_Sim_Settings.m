function [simCmdParamValStructs,rc,mg] = Generate_Sim_Settings(rampconst,mingeardiff,rtp)
% Copyright 2011-2025 The MathWorks, Inc.


numParamSets = length(rampconst)*length(mingeardiff);

% Create parameter sets:
paramSets = cell(1, numParamSets);
pSetNum = 0;
for rc_i = 1:length(rampconst)
    for mgd_i = 1:length(mingeardiff)
        pSetNum = pSetNum+1;
        [Upshift_Speeds Downshift_Speeds Pedal_Positions] = Calc_Shift_Map_RO(rampconst(rc_i),mingeardiff(mgd_i));
        paramSets{pSetNum} = Simulink.BlockDiagram.modifyTunableParameters(rtp, ...
            'Upshift_Speeds',Upshift_Speeds,...
            'Downshift_Speeds',Downshift_Speeds);
        rc(pSetNum) = rampconst(rc_i);
        mg(pSetNum) = mingeardiff(mgd_i);
    end
end

%% Create SIM Command Argument Sets

numSimCmdArgStructs = numParamSets;
simCmdParamValStructs = cell(1, numSimCmdArgStructs);

paramValStruct.RapidAcceleratorUpToDateCheck = 'off';
paramValStruct.RapidAcceleratorParameterSets = [];
paramValStruct.SimulationMode = 'rapid';

for paramSetsIdx = 1:numParamSets
    simCmdParamValStructs{paramSetsIdx} = paramValStruct;
    simCmdParamValStructs{paramSetsIdx}.RapidAcceleratorParameterSets = ...
        paramSets{paramSetsIdx};
end
