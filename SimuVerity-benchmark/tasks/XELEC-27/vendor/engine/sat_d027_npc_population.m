function out=sat_d027_npc_population(modelName)
%SAT_D027_NPC_POPULATION D027-only NPC population semantics.
% A genuine SPS Three-Level Bridge or Three-Level NPC Converter is
% equivalent to the documented 12 controllable switches plus 6 clamping
% diodes only when all of the following hold:
%   * exact MathWorks mask/library identity (visible text is insufficient),
%   * either the documented bridge parameters or an exact 12/6 masked NPC
%     implementation,
%   * the documented signal inputs and six conserving power terminals, and
%   * at least two trusted DC sources reach it and it lies on the resulting
%     split-DC/source-to-three-phase-load path.
% Discrete implementations retain the source population counts.  This
% helper is intentionally task-owned; D025's discrete-cell contract is not
% routed through it.

modelName=char(string(modelName));
P=sat_prims();
out=struct('schema',"simuverity.d027-npc-population.v1", ...
    'model',string(modelName), ...
    'discrete_switch_count',P.count_mask(modelName, ...
        {'igbt','mosfet','gto','ideal switch'}), ...
    'discrete_clamping_diode_count',P.count_mask(modelName,{'^diode$'}), ...
    'aggregate_rows',empty_rows(), ...
    'trusted_dc_source_blocks',strings(0,1), ...
    'active_aggregate_blocks',strings(0,1), ...
    'active_aggregate_count',0, ...
    'equivalent_switch_count',0, ...
    'equivalent_clamping_diode_count',0);

G=sat_model_graph(modelName);
blocks=find_system(modelName,'LookUnderMasks','all','FollowLinks','on', ...
    'Type','Block');
dcSources=trusted_dc_sources(blocks);
out.trusted_dc_source_blocks=dcSources;
rows=empty_rows();
for i=1:numel(blocks)
    block=blocks{i};
    mask=normalise(getp(block,'MaskType'));
    reference=normalise(getp(block,'ReferenceBlock'));
    source=normalise(getp(block,'SourceBlock'));
    bridgeIdentity=mask=="three-level bridge" ...
        &&(contains(reference,"spsthreelevelbridgelib/three-level bridge") ...
        ||contains(source,"spsthreelevelbridgelib/three-level bridge"));
    npcIdentity=mask=="three-level npc converter" ...
        &&(contains(reference,"sps_lib/power electronics/three-level npc converter") ...
        ||contains(reference,"spsthreelevelnpcconverterlib/three-level npc converter") ...
        ||contains(source,"spsthreelevelnpcconverterlib/three-level npc converter"));
    identityOk=bridgeIdentity||npcIdentity;
    if ~identityOk
        continue;
    end

    armsRaw=string(getp(block,'Arms'));
    arms=str2double(armsRaw);
    device=normalise(getp(block,'Device'));
    armsOk=bridgeIdentity&&isfinite(arms)&&arms==3;
    deviceOk=bridgeIdentity&&contains(device,"igbt")&&contains(device,"diode");
    internalSwitchCount=P.count_mask(block, ...
        {'igbt','mosfet','gto','ideal switch'});
    internalClampingDiodeCount=P.count_mask(block,{'^diode$'});
    internalPopulationOk=npcIdentity&&internalSwitchCount==12 ...
        &&internalClampingDiodeCount==6;
    populationOk=(bridgeIdentity&&armsOk&&deviceOk)||internalPopulationOk;
    [gateInputs,physicalPorts]=port_counts(block);
    portOk=physicalPorts==6 ...
        &&((bridgeIdentity&&gateInputs==1)||(npcIdentity&&gateInputs==2));

    q=struct('network',"physical",'direction',"undirected", ...
        'source',struct('descriptor_regex', ...
            'dc voltage source|split dc|dc source'), ...
        'target',struct('descriptor_regex', ...
            'three[- ]phase.*load|series rlc branch|parallel rlc load'));
    q.via={struct('block',string(block))};
    [pathOk,pathEvidence]=sat_graph_query(G,q);
    [splitSourceCount,splitSourceBlocks,splitSourcePaths]= ...
        dc_sources_reaching_stage(G,dcSources,string(block));
    splitDcOk=splitSourceCount>=2;
    active=identityOk&&populationOk&&portOk&&pathOk&&splitDcOk;
    rows(end+1)=struct( ... %#ok<AGROW>
        'block',string(block),'mask_type',mask, ...
        'reference_block',reference,'source_block',source, ...
        'representation',ternary(npcIdentity,"npc_converter","three_level_bridge"), ...
        'arms_raw',armsRaw,'arms',arms, ...
        'device',device,'trusted_identity',logical(identityOk), ...
        'three_arms',logical(armsOk),'igbt_diodes',logical(deviceOk), ...
        'internal_switch_count',internalSwitchCount, ...
        'internal_clamping_diode_count',internalClampingDiodeCount, ...
        'internal_population_ok',logical(internalPopulationOk), ...
        'population_contract_ok',logical(populationOk), ...
        'gate_input_count',gateInputs,'physical_port_count',physicalPorts, ...
        'port_contract_ok',logical(portOk),'on_active_power_path',logical(pathOk), ...
        'split_dc_source_count',splitSourceCount, ...
        'split_dc_source_blocks',splitSourceBlocks, ...
        'split_dc_source_paths',{splitSourcePaths}, ...
        'split_dc_contract_ok',logical(splitDcOk), ...
        'active',logical(active),'physical_path',pathEvidence);
end

out.aggregate_rows=rows;
if ~isempty(rows)
    activeRows=rows([rows.active]);
    out.active_aggregate_blocks=string({activeRows.block})';
end
out.active_aggregate_count=numel(out.active_aggregate_blocks);
activeRows=rows([rows.active]);
embeddedSwitches=sum([activeRows.internal_switch_count]);
embeddedDiodes=sum([activeRows.internal_clamping_diode_count]);
out.equivalent_switch_count=max(0,out.discrete_switch_count-embeddedSwitches) ...
    +12*out.active_aggregate_count;
out.equivalent_clamping_diode_count= ...
    max(0,out.discrete_clamping_diode_count-embeddedDiodes) ...
    +6*out.active_aggregate_count;
end

function rows=empty_rows()
rows=struct('block',{},'mask_type',{},'reference_block',{}, ...
    'source_block',{},'representation',{}, ...
    'arms_raw',{},'arms',{},'device',{},'trusted_identity',{}, ...
    'three_arms',{},'igbt_diodes',{},'gate_input_count',{}, ...
    'internal_switch_count',{},'internal_clamping_diode_count',{}, ...
    'internal_population_ok',{},'population_contract_ok',{}, ...
    'physical_port_count',{},'port_contract_ok',{}, ...
    'on_active_power_path',{},'split_dc_source_count',{}, ...
    'split_dc_source_blocks',{},'split_dc_source_paths',{}, ...
    'split_dc_contract_ok',{},'active',{},'physical_path',{});
end

function value=ternary(condition,yes,no)
if condition,value=yes;else,value=no;end
end

function blocks=trusted_dc_sources(allBlocks)
blocks=strings(0,1);
for i=1:numel(allBlocks)
    block=allBlocks{i};
    mask=normalise(getp(block,'MaskType'));
    reference=normalise(getp(block,'ReferenceBlock'));
    if mask=="dc voltage source" ...
            &&contains(reference,"spsdcvoltagesourcelib/dc voltage source")
        blocks(end+1,1)=string(block); %#ok<AGROW>
    end
end
blocks=unique(blocks,'stable');
end

function [count,reaching,paths]=dc_sources_reaching_stage(G,sources,stage)
reaching=strings(0,1);paths={};
for i=1:numel(sources)
    q=struct('network',"physical",'direction',"undirected", ...
        'source',struct('block',sources(i)), ...
        'target',struct('block',stage));
    [ok,evidence]=sat_graph_query(G,q);
    if ok
        reaching(end+1,1)=sources(i); %#ok<AGROW>
        paths{end+1,1}=evidence; %#ok<AGROW>
    end
end
count=numel(reaching);
end

function [signalInputs,physicalPorts]=port_counts(block)
signalInputs=0;physicalPorts=0;
ph=[];try,ph=get_param(block,'PortHandles');catch,end
if isempty(ph),return;end
if isfield(ph,'Inport')
    for h=double(ph.Inport(:)')
        if h>0&&~strcmpi(getp(h,'PortType'),'connection')
            signalInputs=signalInputs+1;
        end
    end
end
for name={'LConn','RConn'}
    if ~isfield(ph,name{1}),continue;end
    for h=double(ph.(name{1})(:)')
        if h>0&&strcmpi(getp(h,'PortType'),'connection')
            physicalPorts=physicalPorts+1;
        end
    end
end
end

function value=getp(object,param)
value='';try,value=get_param(object,param);catch,end
if isnumeric(value),value=num2str(value);end
end

function value=normalise(value)
value=lower(regexprep(strtrim(string(value)),'\s+',' '));
value=replace(value,'\','/');
end

