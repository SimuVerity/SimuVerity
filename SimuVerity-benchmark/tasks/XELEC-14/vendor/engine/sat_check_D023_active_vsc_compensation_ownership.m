function report=sat_check_D023_active_vsc_compensation_ownership(modelName,spec,scenarioId,simOut,signals,baseReports,state) %#ok<INUSD>
%SAT_CHECK_D023_ACTIVE_VSC_COMPENSATION_OWNERSHIP
% Bind the public Icomp measurement to the real shunt converter/split-link
% branch.  The proof is deliberately controller-independent: PI, PR,
% hysteresis, predictive control and other valid strategies are equivalent.

report=base_report(scenarioId);report.evaluated=true;
[baseOk,baseRows]=required_base_reports(baseReports, ...
    ["controllable_bridge","three_phase_stage","source_vsc_dc_link_path"]);
fixture=unit_test_facts(modelName,state);
if ~isempty(fixture)
    measurements=string(fixture.measurement_blocks);
    caps=string(fixture.dc_capacitors);pairs=fixture.candidate_pairs;
    good=false(1,numel(pairs));
    for i=1:numel(pairs)
        good(i)=logical(pairs(i).physical_ok)&&logical(pairs(i).pcc_ok) ...
            &&double(pairs(i).dc_cap_count)>=2;
    end
else
    measurements=output_trace_blocks(baseReports,"Icomp", ...
        'current measurement|three-phase vi measurement|current and voltage sensor');
    try,G=sat_model_graph(modelName);catch ex
        report.detail="GRAPH_BUILD_ERROR:"+string(ex.identifier);return;
    end
    caps=unique_blocks(G,"physical", ...
        'capacitor|dc[- ]?link|split[- ]?link|dc cap');
    pairs=struct('measurement',{},'physical_ok',{},'pcc_ok',{}, ...
        'dc_cap_count',{},'dc_paths',{},'pcc_path',{});
    for i=1:numel(measurements)
        qPcc=struct('network',"physical",'direction',"undirected", ...
            'source',struct('block',measurements(i)), ...
            'target',struct('descriptor_regex', ...
            'three-phase source|3-ph source|grid source|non.?linear.*load'));
        [pccOk,pccEvidence]=sat_graph_query(G,qPcc);
        capCount=0;dcPaths=strings(0,1);
        for j=1:numel(caps)
            q=struct('network',"physical",'direction',"undirected", ...
                'source',struct('block',measurements(i)), ...
                'target',struct('block',caps(j)));
            q.via={struct('descriptor_regex', ...
                'universal bridge|vsc|converter|inverter|igbt|mosfet|gto|ideal switch')};
            [ok,e]=sat_graph_query(G,q);
            if ok,capCount=capCount+1;dcPaths=[dcPaths;string(e.block_path(:))];end %#ok<AGROW>
        end
        pairs(end+1)=struct('measurement',measurements(i), ... %#ok<AGROW>
            'physical_ok',logical(capCount>=2),'pcc_ok',logical(pccOk), ...
            'dc_cap_count',capCount,'dc_paths',unique(dcPaths,'stable'), ...
            'pcc_path',pccEvidence.block_path);
    end
    good=false(1,numel(pairs));
    for i=1:numel(pairs),good(i)=pairs(i).physical_ok&&pairs(i).pcc_ok&&pairs(i).dc_cap_count>=2;end
end
report.valid=logical(baseOk&&~isempty(measurements)&&~isempty(pairs));
report.ok=logical(report.valid&&any(good));report.score=double(report.ok);
report.evidence=struct('base_reports',baseRows, ...
    'Icomp_trace_measurements',measurements,'dc_capacitors',caps, ...
    'candidate_branches',pairs,'valid_active_branch_count',sum(good), ...
    'controller_constraint',"none");
if ~baseOk,report.detail="D023_BASE_PHYSICAL_CONTRACT_FAILED";
elseif isempty(measurements),report.detail="ICOMP_PHYSICAL_MEASUREMENT_NOT_BOUND";
elseif ~any(good),report.detail="ICOMP_SHUNT_CONVERTER_SPLIT_LINK_OWNERSHIP_NOT_PROVEN";
else,report.detail="OK";end
end

function facts=unit_test_facts(model,state)
facts=[];
if isstruct(model)&&isfield(model,'schema')&&string(model.schema)=="D023.semantic-fixture"
    facts=model;
elseif isstruct(state)&&isfield(state,'evidence')&&isstruct(state.evidence) ...
        &&isfield(state.evidence,'unit_test_facts')
    candidate=state.evidence.unit_test_facts;
    if isstruct(candidate)&&isfield(candidate,'schema') ...
            &&string(candidate.schema)=="D023.semantic-fixture",facts=candidate;end
end
if isempty(facts),return;end
required={'measurement_blocks','dc_capacitors','candidate_pairs'};
assert(all(isfield(facts,required)),'SimuVerity:D023:FixtureSchema', ...
    'D023 semantic fixture is incomplete.');
end
function blocks=output_trace_blocks(base,name,pattern)
blocks=strings(0,1);rows=struct([]);
if isstruct(base)&&isfield(base,'output_reports'),rows=base.output_reports;end
if ~isstruct(rows)||~isfield(rows,'name'),return;end
hit=find(string({rows.name})==string(name));
if numel(hit)~=1||~isfield(rows(hit),'trace'),return;end
trace=rows(hit).trace;if iscell(trace),trace=[trace{:}];end
if ~isstruct(trace),return;end
for i=1:numel(trace)
    text="";if isfield(trace(i),'path'),text=text+" "+string(trace(i).path);end
    if isfield(trace(i),'mask_type'),text=text+" "+string(trace(i).mask_type);end
    if isfield(trace(i),'reference_block'),text=text+" "+string(trace(i).reference_block);end
    if ~isempty(regexpi(char(text),pattern,'once'))&&isfield(trace(i),'path')
        blocks(end+1,1)=string(trace(i).path); %#ok<AGROW>
    end
end
blocks=unique(blocks,'stable');
end
function blocks=unique_blocks(G,network,pattern)
ix=find([G.nodes.network]==string(network));blocks=strings(0,1);
for i=ix(:)'
    if ~isempty(regexpi(char(G.nodes(i).descriptor),pattern,'once'))
        blocks(end+1,1)=G.nodes(i).block; %#ok<AGROW>
    end
end
blocks=unique(blocks,'stable');
end
function [ok,rows]=required_base_reports(base,ids)
ok=true;rows=struct('id',{},'found',{},'passed',{});source=struct([]);
if isstruct(base)&&isfield(base,'struct_reports'),source=base.struct_reports;end
for i=1:numel(ids)
    hit=[];if isstruct(source)&&isfield(source,'id'),hit=find(string({source.id})==ids(i));end
    passed=numel(hit)==1&&logical(source(hit).ok);
    rows(end+1)=struct('id',ids(i),'found',numel(hit)==1,'passed',logical(passed)); %#ok<AGROW>
    ok=ok&&passed;
end
end
function r=base_report(scenario)
r=struct('task',"D023",'id',"D023.active_vsc_compensation_ownership", ...
    'kind',"task_specific",'semantic_kind',"structure",'scenario',string(scenario), ...
    'layer',"qualification",'evaluated',false,'mandatory',true,'ok',false, ...
    'valid',false,'score',0,'detail',"UNINITIALIZED",'evidence',struct());
end
