function report=sat_check_D028_active_phase_shift_branch_ownership(modelName,spec,scenarioId,simOut,signals,baseReports,state) %#ok<INUSD>
%SAT_CHECK_D028_ACTIVE_PHASE_SHIFT_BRANCH_OWNERSHIP
% Bind each active six-pulse diode group to the *first transformer winding*
% reached from its AC terminal(s).  The search is deliberately stopped at
% transformer and bridge interiors, so a branch cannot borrow a decorative
% transformer through the common source or through another bridge and the
% common DC bus.

report=base_report(scenarioId);report.evaluated=true;cfg=find_check(spec,report.id);
if isempty(cfg),report.detail="TASK_CHECK_SPEC_MISSING";return;end

if is_semantic_fixture(modelName)
    [groups,unresolved,inventory]=fixture_groups(modelName);
    bridges=string({modelName.groups.bridge})';
    transformers=string({modelName.groups.transformer})';
else
    try,G=sat_model_graph(modelName);catch ex
        report.detail="GRAPH_BUILD_ERROR:"+string(ex.identifier);return;
    end
    bridges=find_diode_bridges(modelName);transformers=find_transformers(modelName);
    [groups,unresolved,inventory]=production_groups(G,bridges,transformers);
end

lattice=sat_D028_phase_lattice(groups,cfg);
countContract=active_group_count_contract(numel(groups),cfg);
ownership=common_ownership_contract(groups);
report.valid=logical(lattice.valid&&countContract.valid&&ownership.valid&&isempty(unresolved));
report.ok=logical(report.valid&&countContract.ok&&lattice.ok&&ownership.ok);
report.score=double(report.ok);
report.evidence=struct( ...
    'diode_bridge_candidates',unique(bridges,'stable'), ...
    'transformer_candidates',unique(transformers,'stable'), ...
    'active_groups',groups,'unresolved_groups',unresolved, ...
    'branch_inventory',inventory,'active_group_count_contract',countContract, ...
    'phase_lattice',lattice,'common_ownership',ownership);
if ~isempty(unresolved),report.detail="ACTIVE_GROUP_LOCAL_BINDING_UNRESOLVED";
elseif ~countContract.valid,report.detail=countContract.reason;
elseif ~countContract.ok,report.detail=countContract.reason;
elseif ~lattice.valid,report.detail="ACTIVE_GROUP_PHASE_UNRESOLVED";
elseif ~lattice.ok,report.detail=lattice.reason;
elseif ~ownership.valid,report.detail=ownership.reason;
else,report.detail=ownership.reason;end
end

function tf=is_semantic_fixture(x)
tf=isstruct(x)&&isscalar(x)&&isfield(x,'schema') ...
    &&string(x.schema)=="D028.semantic-fixture";
end

function [groups,unresolved,inventory]=fixture_groups(f)
groups=empty_groups();unresolved=strings(0,1);inventory=empty_inventory();
required={'bridge','transformer','winding_port','phase_deg','candidate_active', ...
    'feeds_output','local_supply','phase_resolved','supply_crosses_bridge', ...
    'source','source_trusted','dc_combiner','load','load_trusted', ...
    'output_sensor','combine_reached'};
if ~isfield(f,'groups')||~isstruct(f.groups)
    unresolved="SEMANTIC_FIXTURE_SCHEMA_INVALID";return;
end
rows=f.groups;
if isempty(rows),return;end
if ~all(isfield(rows,required))
    unresolved="SEMANTIC_FIXTURE_SCHEMA_INVALID";return;
end
for i=1:numel(rows)
    x=rows(i);[active,activeValid]=scalar_logical(x.candidate_active);
    [out,outValid]=scalar_logical(x.feeds_output);
    [local,localValid]=scalar_logical(x.local_supply);
    [resolved,resolvedValid]=scalar_logical(x.phase_resolved);
    [borrowed,borrowedValid]=scalar_logical(x.supply_crosses_bridge);
    [sourceTrusted,sourceTrustedValid]=scalar_logical(x.source_trusted);
    [loadTrusted,loadTrustedValid]=scalar_logical(x.load_trusted);
    [combineReached,combineReachedValid]=scalar_logical(x.combine_reached);
    schemaOk=all([activeValid outValid localValid resolvedValid borrowedValid ...
        sourceTrustedValid loadTrustedValid combineReachedValid]) ...
        &&isscalar(x.phase_deg)&&isnumeric(x.phase_deg)&&isfinite(x.phase_deg) ...
        &&strlength(string(x.bridge))>0&&strlength(string(x.transformer))>0 ...
        &&strlength(string(x.winding_port))>0&&strlength(string(x.source))>0 ...
        &&strlength(string(x.dc_combiner))>0&&strlength(string(x.load))>0 ...
        &&strlength(string(x.output_sensor))>0;
    if ~schemaOk,unresolved(end+1)="SEMANTIC_FIXTURE_SCHEMA_INVALID";return;end %#ok<AGROW>
    row=inventory_row(string(x.bridge));row.output_ok=out;row.local_supply_ok=local&&~borrowed;
    row.phase_ok=resolved;row.phase_deg=double(x.phase_deg);
    row.transformer=string(x.transformer);row.winding_port=string(x.winding_port);
    row.source=string(x.source);row.dc_combiner=string(x.dc_combiner);
    row.load=string(x.load);row.output_sensor=string(x.output_sensor);
    row.source_ok=sourceTrusted;row.combine_ok=combineReached;row.load_ok=loadTrusted;
    row.source_reason=ternary_reason(sourceTrusted,"OK","FIXTURE_SOURCE_UNTRUSTED");
    row.combine_reason=ternary_reason(combineReached,"OK","FIXTURE_COMBINE_UNREACHED");
    row.status="DECORATIVE_OR_DISCONNECTED";
    if active&&out
        if local&&~borrowed&&resolved
            row.status="ACTIVE_LOCAL_GROUP";
            groups(end+1)=struct('bridge',string(x.bridge), ... %#ok<AGROW>
                'transformer',string(x.transformer),'phase_deg',double(x.phase_deg), ...
                'active',true,'supply_path',"fixture-local-ac-path", ...
                'output_path',"fixture-local-dc-path",'source',string(x.source), ...
                'source_path',"fixture-transformer-primary-to-source", ...
                'dc_combiner',string(x.dc_combiner), ...
                'dc_combine_path',"fixture-bridge-to-common-combine", ...
                'load',string(x.load),'load_path',"fixture-combine-to-load", ...
                'output_sensor',string(x.output_sensor), ...
                'ownership_resolved',logical(sourceTrusted&&loadTrusted&&combineReached), ...
                'winding_port',string(x.winding_port), ...
                'phase_evidence',struct('source',"semantic_fixture", ...
                    'raw',double(x.phase_deg)));
        else
            row.status="ACTIVE_LOCAL_BINDING_UNRESOLVED";
            unresolved(end+1)=string(x.bridge)+":LOCAL_SUPPLY_OR_PHASE_UNRESOLVED"; %#ok<AGROW>
        end
    end
    inventory(end+1)=row; %#ok<AGROW>
end
end

function [groups,unresolved,inventory]=production_groups(G,bridges,transformers)
groups=empty_groups();unresolved=strings(0,1);inventory=empty_inventory();
for i=1:numel(bridges)
    bridge=bridges(i);row=inventory_row(bridge);
    [ac,dc,sideOk,sideReason]=bridge_power_sides(G,bridge);
    row.ac_ports=port_labels(G,ac);row.dc_ports=port_labels(G,dc);
    if ~sideOk
        row.status=sideReason;unresolved(end+1)=bridge+":"+sideReason; %#ok<AGROW>
        inventory(end+1)=row;continue; %#ok<AGROW>
    end
    [outOk,outPaths]=feeds_output_locally(G,dc,bridges);
    row.output_ok=outOk;row.output_paths=outPaths;
    if ~outOk
        row.status="OUTPUT_DISCONNECTED";inventory(end+1)=row;continue; %#ok<AGROW>
    end
    [supplyOk,binding,supplyReason]=local_transformer_binding(G,ac,bridges,transformers);
    row.local_supply_ok=supplyOk;row.supply_paths=binding.paths;
    row.transformer=binding.transformer;row.winding_port=binding.winding_port;
    if ~supplyOk
        row.status=supplyReason;unresolved(end+1)=bridge+":"+supplyReason; %#ok<AGROW>
        inventory(end+1)=row;continue; %#ok<AGROW>
    end
    [phase,phaseOk,phaseEvidence]=transformer_winding_phase( ...
        binding.transformer,binding.hit_field,binding.hit_ordinal,binding.group_index);
    row.phase_ok=phaseOk;row.phase_deg=phase;row.phase_evidence=phaseEvidence;
    if ~phaseOk
        row.status="LOCAL_WINDING_PHASE_UNRESOLVED";
        unresolved(end+1)=bridge+":LOCAL_WINDING_PHASE_UNRESOLVED"; %#ok<AGROW>
        inventory(end+1)=row;continue; %#ok<AGROW>
    end
    [sourceOk,sourceBinding]=transformer_primary_source_binding( ...
        G,binding,bridges,transformers);
    [combineOk,dcBinding]=dc_common_network_binding(G,dc,bridges);
    row.source_ok=sourceOk;row.source=sourceBinding.source;
    row.source_reason=sourceBinding.reason;
    row.source_paths=sourceBinding.paths;
    row.combine_ok=combineOk;row.dc_combiner=dcBinding.combiner_key;
    row.combine_reason=dcBinding.reason;
    row.dc_combine_paths=dcBinding.combine_paths;
    row.load_ok=strlength(dcBinding.load)>0;row.load=dcBinding.load;
    row.load_paths=dcBinding.load_paths;row.output_sensor=dcBinding.output_sensor;
    row.output_sensor_paths=dcBinding.output_sensor_paths;
    if sourceOk&&combineOk,row.status="ACTIVE_LOCAL_GROUP";
    else,row.status="ACTIVE_GROUP_OWNERSHIP_UNRESOLVED";end
    groups(end+1)=struct('bridge',bridge,'transformer',binding.transformer, ... %#ok<AGROW>
        'phase_deg',phase,'active',true,'supply_path',binding.paths, ...
        'output_path',outPaths,'source',sourceBinding.source, ...
        'source_path',sourceBinding.paths,'dc_combiner',dcBinding.combiner_key, ...
        'dc_combine_path',dcBinding.combine_paths,'load',dcBinding.load, ...
        'load_path',dcBinding.load_paths,'output_sensor',dcBinding.output_sensor, ...
        'ownership_resolved',logical(sourceOk&&combineOk), ...
        'winding_port',binding.winding_port, ...
        'phase_evidence',phaseEvidence);
    inventory(end+1)=row; %#ok<AGROW>
end
end

function result=active_group_count_contract(observed,cfg)
exact=getnum(cfg,'exact_active_six_pulse_groups',NaN);
if isfinite(exact)
    lo=exact;hi=exact;
else
    lo=getnum(cfg,'min_active_six_pulse_groups',4);
    % A 24-pulse converter has exactly four active six-pulse groups.  A
    % source spec that only declares min=4 must not silently admit a 30- or
    % 48-pulse stage with duplicated phase classes.
    hi=getnum(cfg,'max_active_six_pulse_groups',4);
end
valid=isfinite(lo)&&isfinite(hi)&&lo>=0&&hi>=lo ...
    &&abs(lo-round(lo))<1e-12&&abs(hi-round(hi))<1e-12;
ok=valid&&observed>=lo&&observed<=hi;
if ~valid,reason="ACTIVE_GROUP_COUNT_SPEC_INVALID";
elseif observed<lo,reason="TOO_FEW_ACTIVE_GROUPS";
elseif observed>hi,reason="TOO_MANY_ACTIVE_GROUPS";
else,reason="OK";end
evidenceLo=lo;evidenceHi=hi;
if ~isfinite(evidenceLo),evidenceLo=[];end
if ~isfinite(evidenceHi),evidenceHi=[];end
result=struct('valid',logical(valid),'ok',logical(ok),'reason',reason, ...
    'observed',double(observed),'min',evidenceLo,'max',evidenceHi, ...
    'exact',logical(valid&&lo==hi));
end

function result=common_ownership_contract(groups)
result=struct('valid',false,'ok',false,'reason',"OWNERSHIP_UNRESOLVED", ...
    'sources',strings(0,1),'combiner_keys',strings(0,1), ...
    'loads',strings(0,1),'output_sensors',strings(0,1));
if isempty(groups)
    result.valid=true;result.reason="NO_ACTIVE_GROUPS";return;
end
required={'source','dc_combiner','load','output_sensor','ownership_resolved'};
if ~all(isfield(groups,required))
    result.reason="OWNERSHIP_EVIDENCE_SCHEMA_INVALID";return;
end
result.sources=string({groups.source})';
result.combiner_keys=string({groups.dc_combiner})';
result.loads=string({groups.load})';
result.output_sensors=string({groups.output_sensor})';
resolved=logical([groups.ownership_resolved]);
if any(~resolved)||any(strlength(result.sources)==0) ...
        ||any(strlength(result.combiner_keys)==0)||any(strlength(result.loads)==0) ...
        ||any(strlength(result.output_sensors)==0)
    result.reason="ACTIVE_GROUP_OWNERSHIP_UNRESOLVED";return;
end
result.valid=true;
if numel(unique(result.sources))~=1
    result.reason="ACTIVE_GROUPS_DO_NOT_SHARE_SOURCE";return;
elseif numel(unique(result.combiner_keys))~=1
    result.reason="ACTIVE_GROUPS_DO_NOT_SHARE_DC_COMBINER";return;
elseif numel(unique(result.loads))~=1
    result.reason="ACTIVE_GROUPS_DO_NOT_SHARE_LOAD";return;
elseif numel(unique(result.output_sensors))~=1
    result.reason="ACTIVE_GROUPS_DO_NOT_SHARE_OUTPUT_SENSOR";return;
end
result.ok=true;result.reason="OK";
end

function [ok,binding]=transformer_primary_source_binding(G,winding,bridges,transformers)
binding=struct('source',"",'paths',strings(0,1),'primary_ports',strings(0,1), ...
    'candidate_sources',strings(0,1),'reason',"PRIMARY_SIDE_UNRESOLVED");
ids=block_physical_nodes(G,winding.transformer);
fields=string({G.nodes(ids).port_field});hitField=string(winding.hit_field);
if strcmpi(hitField,"LConn"),primary=ids(strcmpi(fields,"RConn"));
elseif strcmpi(hitField,"RConn"),primary=ids(strcmpi(fields,"LConn"));
else,primary=[];end
primary=sort_by_ordinal(G,primary);binding.primary_ports=port_labels(G,primary);
sources=trusted_three_phase_sources(G);binding.candidate_sources=sources;
if isempty(primary)||isempty(sources),ok=false;return;end
paths=strings(0,1);hits=strings(0,1);
for i=1:numel(primary)
    [found,blocks,p]=nearest_trusted_blocks(G,primary(i),sources, ...
        unique([string(bridges(:));string(transformers(:))],'stable'),true);
    if ~found||numel(blocks)~=1,ok=false;binding.reason="PRIMARY_SOURCE_UNRESOLVED_OR_AMBIGUOUS";return;end
    hits(end+1,1)=blocks(1);paths(end+1,1)=path_label(G,p); %#ok<AGROW>
end
u=unique(hits,'stable');ok=numel(u)==1;
if ok,binding.source=u(1);binding.paths=paths;binding.reason="OK";
else,binding.reason="PRIMARY_PHASES_REACH_DIFFERENT_SOURCES";end
end

function [ok,binding]=dc_common_network_binding(G,dc,bridges)
binding=struct('combiner_key',"",'combine_paths',strings(0,1), ...
    'load',"",'load_paths',strings(0,1),'output_sensor',"", ...
    'output_sensor_paths',strings(0,1),'reason',"DC_COMBINER_UNRESOLVED");
combiners=trusted_dc_combiners(G);
if numel(dc)~=2||isempty(combiners),ok=false;return;end
hitBlocks=strings(0,1);hitNodes=[];hitFields=strings(0,1);paths=strings(0,1);
for i=1:numel(dc)
    [found,blocks,p,nodes]=nearest_trusted_blocks(G,dc(i),combiners,string(bridges),false);
    if ~found||numel(blocks)~=1||isempty(nodes)
        ok=false;binding.reason="DC_TERMINAL_COMBINER_UNRESOLVED_OR_AMBIGUOUS";return;
    end
    pick=nodes(1);hitBlocks(end+1,1)=blocks(1);hitNodes(end+1)=pick; %#ok<AGROW>
    hitFields(end+1,1)=string(G.nodes(pick).port_field);paths(end+1,1)=path_label(G,p); %#ok<AGROW>
end
keys=hitBlocks+"["+hitFields+"]";
if numel(unique(keys))~=numel(keys)
    ok=false;binding.reason="DC_TERMINALS_COLLAPSE_TO_ONE_COMBINER_INPUT";return;
end
commonBlocks=unique(hitBlocks,'stable');
binding.combiner_key=strjoin(sort(commonBlocks),"|");binding.combine_paths=paths;

loads=trusted_dc_loads(G,commonBlocks);sensors=trusted_voltage_sensors(G);
if isempty(loads)||isempty(sensors)
    ok=false;binding.reason="TRUSTED_DC_LOAD_OR_SENSOR_NOT_FOUND";return;
end
loadHits=strings(0,1);sensorHits=strings(0,1);
loadPaths=strings(0,1);sensorPaths=strings(0,1);
for i=1:numel(commonBlocks)
    fieldsForBlock=hitFields(hitBlocks==commonBlocks(i));
    starts=combiner_output_nodes(G,commonBlocks(i),fieldsForBlock);
    if isempty(starts),ok=false;binding.reason="COMBINER_OUTPUT_PORT_UNRESOLVED";return;end
    for q=1:numel(starts)
        [foundLoad,blocksLoad,pLoad]=nearest_trusted_blocks(G,starts(q),loads, ...
            unique([string(bridges(:));commonBlocks(:)],'stable'),false);
        [foundSensor,blocksSensor,pSensor]=nearest_trusted_blocks(G,starts(q),sensors, ...
            unique([string(bridges(:));commonBlocks(:)],'stable'),false);
        if ~foundLoad||numel(blocksLoad)~=1||~foundSensor||numel(blocksSensor)~=1
            ok=false;binding.reason="COMBINER_OUTPUT_LOAD_OR_SENSOR_UNRESOLVED";return;
        end
        loadHits(end+1,1)=blocksLoad(1);sensorHits(end+1,1)=blocksSensor(1); %#ok<AGROW>
        loadPaths(end+1,1)=path_label(G,pLoad);sensorPaths(end+1,1)=path_label(G,pSensor); %#ok<AGROW>
    end
end
uLoad=unique(loadHits,'stable');uSensor=unique(sensorHits,'stable');
if numel(uLoad)~=1,ok=false;binding.reason="COMBINER_OUTPUTS_DO_NOT_SHARE_LOAD";return;end
if numel(uSensor)~=1,ok=false;binding.reason="COMBINER_OUTPUTS_DO_NOT_SHARE_SENSOR";return;end
binding.load=uLoad(1);binding.output_sensor=uSensor(1);
binding.load_paths=loadPaths;binding.output_sensor_paths=sensorPaths;
binding.reason="OK";ok=true;
end

function starts=combiner_output_nodes(G,block,inputFields)
ids=block_physical_nodes(G,block);fields=string({G.nodes(ids).port_field});
inputFields=unique(lower(string(inputFields)));
if numel(inputFields)==1&&inputFields=="lconn",starts=ids(strcmpi(fields,"RConn"));
elseif numel(inputFields)==1&&inputFields=="rconn",starts=ids(strcmpi(fields,"LConn"));
else,starts=[];end
starts=sort_by_ordinal(G,starts);
end

function blocks=trusted_three_phase_sources(G)
blocks=unique(string({G.nodes.block}),'stable');keep=false(size(blocks));
for i=1:numel(blocks),keep(i)=is_trusted_three_phase_source(blocks(i));end
blocks=blocks(keep);
end

function tf=is_trusted_three_phase_source(block)
mt=normtext(getp(char(block),'MaskType'));rb=normtext(getp(char(block),'ReferenceBlock'));
cp=normtext(getp(char(block),'ComponentPath'));d=mt+"|"+rb+"|"+cp;
tf=contains(d,'voltage source (three-phase)')||contains(d,'three-phase source') ...
    ||contains(d,'ee.sources.voltage.abc');
end

function blocks=trusted_dc_combiners(G)
blocks=unique(string({G.nodes.block}),'stable');keep=false(size(blocks));
for i=1:numel(blocks),keep(i)=is_trusted_dc_combiner(G,blocks(i));end
blocks=blocks(keep);
end

function tf=is_trusted_dc_combiner(G,block)
mt=normtext(getp(char(block),'MaskType'));rb=normtext(getp(char(block),'ReferenceBlock'));
if contains(mt,'interphase transformer')||contains(rb,'interphase transformer'),tf=true;return;end
tf=false;if ~strcmpi(getp(char(block),'BlockType'),'SubSystem'),return;end
ids=block_physical_nodes(G,block);fields=string({G.nodes(ids).port_field});
if sum(strcmpi(fields,"LConn"))<4||sum(strcmpi(fields,"RConn"))<1,return;end
children=find_system(char(block),'SearchDepth',1,'LookUnderMasks','all','FollowLinks','on','Type','Block');
nMutual=0;
for i=1:numel(children)
    c=children{i};if strcmp(c,char(block)),continue;end
    cm=normtext(getp(c,'MaskType'));cr=normtext(getp(c,'ReferenceBlock'));
    if contains(cm,'mutual inductor')||contains(cr,'mutual inductor'),nMutual=nMutual+1;end
end
tf=nMutual>=4;
end

function blocks=trusted_dc_loads(G,excludeParents)
blocks=unique(string({G.nodes.block}),'stable');keep=false(size(blocks));
for i=1:numel(blocks)
    b=blocks(i);inside=false;
    for p=string(excludeParents(:))',inside=inside||startsWith(b,p+"/");end
    if inside,continue;end
    mt=normtext(getp(char(b),'MaskType'));rb=normtext(getp(char(b),'ReferenceBlock'));
    bt=normtext(getp(char(b),'BlockType'));branch=upper(strtrim(getp(char(b),'BranchType')));
    keep(i)=contains(mt,'resistor')||contains(rb,'/resistor') ...
        ||contains(mt,'dc load')||(contains(mt,'rlc branch')&&branch=="R") ...
        ||(bt=="resistor");
end
blocks=blocks(keep);
end

function blocks=trusted_voltage_sensors(G)
blocks=unique(string({G.nodes.block}),'stable');keep=false(size(blocks));
for i=1:numel(blocks)
    mt=normtext(getp(char(blocks(i)),'MaskType'));
    rb=normtext(getp(char(blocks(i)),'ReferenceBlock'));
    keep(i)=(contains(mt,'voltage sensor')||contains(mt,'voltage measurement') ...
        ||contains(rb,'voltage sensor')||contains(rb,'voltage measurement')) ...
        &&~contains(mt,'current and voltage');
end
blocks=blocks(keep);
end

function [found,hitBlocks,path,hitNodes]=nearest_trusted_blocks(G,start,targetBlocks,barriers,augmentVi)
n=numel(G.nodes);dist=inf(1,n);prev=zeros(1,n);dist(start)=0;queue=start;
hits=[];minHit=inf;targetBlocks=string(targetBlocks);barriers=string(barriers);
while ~isempty(queue)
    x=queue(1);queue(1)=[];dx=dist(x);bx=string(G.nodes(x).block);
    if dx>minHit,continue;end
    if dx>0&&any(targetBlocks==bx),minHit=dx;hits(end+1)=x;continue;end %#ok<AGROW>
    [nbr,kinds]=ownership_neighbors(G,x,augmentVi);
    for j=1:numel(nbr)
        y=nbr(j);by=string(G.nodes(y).block);kind=string(kinds{j});
        if kind=="component_internal"&&(any(barriers==bx)||any(barriers==by)),continue;end
        if y~=start&&any(barriers==by)&&~any(targetBlocks==by),continue;end
        if dist(y)<=dx+1,continue;end
        dist(y)=dx+1;prev(y)=x;queue(end+1)=y; %#ok<AGROW>
    end
end
hits=unique(hits,'stable');hitBlocks=unique(string({G.nodes(hits).block}),'stable');
found=~isempty(hits);path=[];hitNodes=hits;
if found,path=restore_path(prev,hits(1));end
end

function [nbr,kinds]=ownership_neighbors(G,x,augmentVi)
nbr=G.physical_undirected{x};kinds=G.physical_edge_kinds{x};
if ~augmentVi,return;end
block=string(G.nodes(x).block);mt=normtext(getp(char(block),'MaskType'));
rb=normtext(getp(char(block),'ReferenceBlock'));cp=normtext(getp(char(block),'ComponentPath'));
trusted=contains(mt,'current and voltage sensor (three-phase)') ...
    ||contains(rb,'current and voltage sensor (three-phase)') ...
    ||contains(cp,'ee.sensors.vi_sensor');
if ~trusted,return;end
ids=block_physical_nodes(G,block);L=sort_by_ordinal(G,ids(strcmpi(string({G.nodes(ids).port_field}),"LConn")));
R=sort_by_ordinal(G,ids(strcmpi(string({G.nodes(ids).port_field}),"RConn")));
if numel(L)==1&&numel(R)>=1,through=[L(1) R(end)];else,return;end
if x==through(1)&&~any(nbr==through(2)),nbr(end+1)=through(2);kinds{end+1}='trusted_vi_sensor_through';
elseif x==through(2)&&~any(nbr==through(1)),nbr(end+1)=through(1);kinds{end+1}='trusted_vi_sensor_through';end
end

function [ac,dc,ok,reason]=bridge_power_sides(G,bridge)
ids=block_physical_nodes(G,bridge);ac=[];dc=[];ok=false;reason="BRIDGE_PORT_SCHEMA_UNSUPPORTED";
L=ids(strcmpi(string({G.nodes(ids).port_field}),"LConn"));
R=ids(strcmpi(string({G.nodes(ids).port_field}),"RConn"));
L=sort_by_ordinal(G,L);R=sort_by_ordinal(G,R);
% SPS Universal Bridge: three scalar AC terminals and two DC terminals.
if numel(L)==3&&numel(R)==2,ac=L;dc=R;ok=true;reason="";return;end
if numel(R)==3&&numel(L)==2,ac=R;dc=L;ok=true;reason="";return;end
% Simscape Rectifier (Three-Phase): one composite three-phase AC port and
% two scalar DC terminals (the official 24-pulse example uses this form).
if numel(L)==1&&numel(R)==2,ac=L;dc=R;ok=true;reason="";return;end
if numel(R)==1&&numel(L)==2,ac=R;dc=L;ok=true;reason="";return;end
end

function [ok,binding,reason]=local_transformer_binding(G,ac,bridges,transformers)
binding=struct('transformer',"",'winding_port',"",'hit_field',"", ...
    'hit_ordinal',[],'group_index',[],'paths',strings(0,1));
ok=false;reason="LOCAL_TRANSFORMER_NOT_FOUND";hits=zeros(1,numel(ac));paths=strings(0,1);
keys=strings(1,numel(ac));blocks=strings(1,numel(ac));groups=zeros(1,numel(ac));
fields=strings(1,numel(ac));ordinals=zeros(1,numel(ac));phaseSlots=zeros(1,numel(ac));
for i=1:numel(ac)
    [hitIds,hitPaths]=nearest_local_transformer(G,ac(i),bridges,transformers);
    if isempty(hitIds),reason="LOCAL_TRANSFORMER_NOT_FOUND";return;end
    candidateKeys=strings(1,numel(hitIds));meta=cell(1,numel(hitIds));
    for q=1:numel(hitIds)
        [key,groupIndex,phaseSlot]=transformer_port_group(G,hitIds(q));
        candidateKeys(q)=string(G.nodes(hitIds(q)).block)+"|"+key;
        meta{q}=struct('key',key,'group',groupIndex,'slot',phaseSlot);
    end
    [u,ia]=unique(candidateKeys,'stable');
    if numel(u)~=1,reason="LOCAL_TRANSFORMER_AMBIGUOUS";return;end
    pick=ia(1);hits(i)=hitIds(pick);blocks(i)=string(G.nodes(hits(i)).block);
    fields(i)=string(G.nodes(hits(i)).port_field);ordinals(i)=G.nodes(hits(i)).port_ordinal;
    keys(i)=meta{pick}.key;groups(i)=meta{pick}.group;phaseSlots(i)=meta{pick}.slot;
    paths(end+1,1)=path_label(G,hitPaths{pick}); %#ok<AGROW>
end
if numel(unique(blocks))~=1||numel(unique(keys))~=1
    reason="AC_PHASES_BIND_DIFFERENT_WINDINGS";return;
end
% Scalar SPS terminals must prove all three phase terminals of one winding;
% a Simscape composite three-phase port proves the triplet in one port.
if numel(ac)==3&&numel(unique(phaseSlots))~=3
    reason="AC_PHASE_TERMINALS_INCOMPLETE";return;
end
binding.transformer=blocks(1);binding.winding_port=keys(1);
binding.hit_field=fields(1);binding.hit_ordinal=ordinals(1);
binding.group_index=groups(1);binding.paths=paths;ok=true;reason="";
end

function [hitIds,hitPaths]=nearest_local_transformer(G,start,bridges,transformers)
n=numel(G.nodes);dist=inf(1,n);prev=zeros(1,n);dist(start)=0;queue=start;
hitIds=[];minHit=inf;bridgeSet=string(bridges);transformerSet=string(transformers);
while ~isempty(queue)
    x=queue(1);queue(1)=[];dx=dist(x);bx=string(G.nodes(x).block);
    if dx>minHit,continue;end
    if dx>0&&any(transformerSet==bx)
        minHit=dx;hitIds(end+1)=x;continue; %#ok<AGROW>
    end
    if dx>0&&any(bridgeSet==bx),continue;end
    nbr=G.physical_undirected{x};kinds=G.physical_edge_kinds{x};
    for j=1:numel(nbr)
        y=nbr(j);by=string(G.nodes(y).block);kind=string(kinds{j});
        if kind=="component_internal"&&(any(bridgeSet==bx)||any(bridgeSet==by)),continue;end
        if y~=start&&any(bridgeSet==by),continue;end
        if dist(y)<=dx+1,continue;end
        dist(y)=dx+1;prev(y)=x;queue(end+1)=y; %#ok<AGROW>
    end
end
hitIds=unique(hitIds,'stable');hitPaths=cell(1,numel(hitIds));
for i=1:numel(hitIds),hitPaths{i}=restore_path(prev,hitIds(i));end
end

function [ok,paths]=feeds_output_locally(G,dc,bridges)
combiners=trusted_dc_combiners(G);
targetBlocks=unique([combiners(:);trusted_dc_loads(G,combiners);trusted_voltage_sensors(G)],'stable');
physical=find(string({G.nodes.network})=="physical");
target=physical(ismember(string({G.nodes(physical).block}),targetBlocks));
paths=strings(0,1);ok=~isempty(dc)&&~isempty(target);
for i=1:numel(dc)
    [found,p]=shortest_local_output(G,dc(i),target,bridges);ok=ok&&found;
    if found,paths(end+1,1)=path_label(G,p);end %#ok<AGROW>
end
end

function [found,path]=shortest_local_output(G,start,target,bridges)
n=numel(G.nodes);seen=false(1,n);prev=zeros(1,n);queue=start;seen(start)=true;
found=false;hit=0;bridgeSet=string(bridges);
while ~isempty(queue)
    x=queue(1);queue(1)=[];if any(target==x),found=true;hit=x;break;end
    bx=string(G.nodes(x).block);nbr=G.physical_undirected{x};kinds=G.physical_edge_kinds{x};
    for j=1:numel(nbr)
        y=nbr(j);by=string(G.nodes(y).block);kind=string(kinds{j});
        if kind=="component_internal"&&(any(bridgeSet==bx)||any(bridgeSet==by)),continue;end
        if y~=start&&any(bridgeSet==by),continue;end
        if seen(y),continue;end;seen(y)=true;prev(y)=x;queue(end+1)=y; %#ok<AGROW>
    end
end
if found,path=restore_path(prev,hit);else,path=[];end
end

function [key,groupIndex,phaseSlot]=transformer_port_group(G,nodeId)
n=G.nodes(nodeId);block=string(n.block);field=string(n.port_field);ord=double(n.port_ordinal);
ids=block_physical_nodes(G,block);same=ids(strcmpi(string({G.nodes(ids).port_field}),field));
count=numel(same);mt=normtext(getp(char(block),'MaskType'));
nPulse=pulse_group_count(getp(char(block),'pulseNumber'));
if contains(mt,'phase-shifting transformer')&&nPulse>0&&count==nPulse
    % Simscape phase-shifting transformer exposes one composite output port
    % per six-pulse group.  Each output is its own winding group.
    chunk=ord;phaseSlot=1;
else
    chunk=floor((ord-1)/3)+1;phaseSlot=mod(ord-1,3)+1;
end
L=ids(strcmpi(string({G.nodes(ids).port_field}),"LConn"));
if strcmpi(field,"LConn"),groupIndex=chunk;else,groupIndex=ceil(numel(L)/3)+chunk;end
key=field+"#"+string(chunk);
end

function [phase,valid,evidence]=transformer_winding_phase(block,field,ordinal,groupIndex)
phase=[];valid=false;observations=struct('parameter',{},'raw',{},'values',{});
mt=normtext(getp(char(block),'MaskType'));
try,dp=get_param(char(block),'DialogParameters');catch,dp=struct();end
names={};if isstruct(dp),names=fieldnames(dp);end

% Simscape Phase-Shifting Transformer is a semantic multi-output block.
% pulseNumber determines the number of six-pulse secondary groups; their
% output-port ordinals define a rotation-equivalent 60/N lattice.
if contains(mt,'phase-shifting transformer')
    pulseRaw=string(getp(char(block),'pulseNumber'));n=pulse_group_count(pulseRaw);
    if n>0&&strcmpi(field,"RConn")&&ordinal>=1&&ordinal<=n
        phase=mod((double(ordinal)-1)*(60/n),60);valid=true;
        evidence=struct('block',string(block),'winding_port',field+"#"+string(ordinal), ...
            'source',"pulseNumber_output_ordinal",'observations', ...
            struct('parameter',"pulseNumber",'raw',pulseRaw,'values',n), ...
            'normalized_candidates',phase);return;
    end
    % SPS Zigzag Phase-Shifting Transformer carries an explicit angle as
    % the second SecondaryVoltage element.
    raw=string(getp(char(block),'SecondaryVoltage'));nums=numeric_literals(raw);
    if numel(nums)>=2
        phase=mod(nums(end),60);valid=true;
        observations=struct('parameter',"SecondaryVoltage",'raw',raw,'values',nums(end));
        evidence=struct('block',string(block),'winding_port',field+"#"+string(groupIndex), ...
            'source',"explicit_phase_shift",'observations',observations, ...
            'normalized_candidates',phase);return;
    end
end

% Prefer an explicit phase/shift/angle parameter when the block provides
% one.  This is independent of block and hierarchy names.
angles=[];
for i=1:numel(names)
    key=lower(string(names{i}));
    if ~(contains(key,'phase')||contains(key,'shift')||contains(key,'angle')),continue;end
    raw=string(getp(char(block),names{i}));vals=numeric_literals(raw);
    if isempty(vals),vals=parse_angles(raw);end
    if ~isempty(vals)
        vals=vals(end);angles=[angles vals];observations(end+1)=struct( ... %#ok<AGROW>
            'parameter',string(names{i}),'raw',raw,'values',vals);
    end
end
if ~isempty(angles)
    u=unique(round(mod(double(angles),60)*1e9)/1e9);valid=numel(u)==1;
    if valid,phase=u(1);end
    evidence=struct('block',string(block),'winding_port',field+"#"+string(groupIndex), ...
        'source',"explicit_phase_parameter",'observations',observations, ...
        'normalized_candidates',u);return;
end

% SPS multi-winding transformer: bind the connection group belonging to
% the concrete terminal group instead of aggregating every winding.
want="winding"+string(groupIndex)+"connection";raw="";param="";
for i=1:numel(names)
    if lower(string(names{i}))==want,param=string(names{i});raw=string(getp(char(block),names{i}));break;end
end
if strlength(raw)==0&&groupIndex>1
    for i=1:numel(names)
        if lower(string(names{i}))=="secondaryconnection",param=string(names{i});raw=string(getp(char(block),names{i}));break;end
    end
end
vals=parse_angles(raw);
if ~isempty(vals)
    u=unique(round(mod(double(vals),60)*1e9)/1e9);valid=numel(u)==1;
    if valid,phase=u(1);end
    observations=struct('parameter',param,'raw',raw,'values',vals);
    evidence=struct('block',string(block),'winding_port',field+"#"+string(groupIndex), ...
        'source',"winding_connection_group",'observations',observations, ...
        'normalized_candidates',u);return;
end

% An ordinary transformer without a phase parameter is a zero-shift
% winding.  Four such blocks therefore remain one phase class and fail.
phase=0;valid=true;observations=struct('parameter',"implicit", ...
    'raw',"ordinary transformer",'values',0);
evidence=struct('block',string(block),'winding_port',field+"#"+string(groupIndex), ...
    'source',"ordinary_zero_shift",'observations',observations, ...
    'normalized_candidates',0);
end

function n=pulse_group_count(raw)
s=lower(char(raw));n=0;
if contains(s,'twentyfour')||~isempty(regexp(s,'(?:^|\D)24(?:\D|$)','once')),n=4;
elseif contains(s,'twelve')||~isempty(regexp(s,'(?:^|\D)12(?:\D|$)','once')),n=2;
elseif contains(s,'six')||~isempty(regexp(s,'(?:^|\D)6(?:\D|$)','once')),n=1;end
end

function bridges=find_diode_bridges(modelName)
bridges=strings(0,1);blocks=find_system(modelName,'LookUnderMasks','all','FollowLinks','on','Type','Block');
for i=1:numel(blocks)
    b=blocks{i};mt=normtext(getp(b,'MaskType'));rb=normtext(getp(b,'ReferenceBlock'));
    cp=normtext(getp(b,'ComponentPath'));
    desc=normtext(string(b)+" "+mt+" "+rb+" "+cp);isBridge=contains(desc,"universal bridge");
    isRectifier3=contains(mt,"rectifier (three-phase)") ...
        &&~contains(mt,"average-value")&&~contains(desc,"controlled");
    if ~isBridge&&~isRectifier3&&isempty(regexpi(char(desc),'six[- ]?pulse diode bridge','once')),continue;end
    if isRectifier3
        bridges(end+1,1)=string(b);continue; %#ok<AGROW>
    end
    device=lower(getp(b,'Device'));arms=str2double(getp(b,'Arms'));
    if contains(device,'diode')&&~contains(device,'igbt')&&~contains(device,'gto') ...
            &&isfinite(arms)&&arms==3
        bridges(end+1,1)=string(b); %#ok<AGROW>
        continue;
    end
    % A six-pulse group may be authored from six ordinary discrete diode
    % blocks inside an otherwise unnamed subsystem.  Recognize that
    % representation from trusted device identities and a 3-AC/2-DC
    % physical boundary, never from the subsystem name.
    if strcmpi(getp(b,'BlockType'),'SubSystem')&&is_discrete_six_diode_group(b)
        bridges(end+1,1)=string(b); %#ok<AGROW>
    end
end
bridges=unique(bridges,'stable');
end

function transformers=find_transformers(modelName)
transformers=strings(0,1);blocks=find_system(modelName,'LookUnderMasks','all','FollowLinks','on','Type','Block');
for i=1:numel(blocks)
    mt=normtext(getp(blocks{i},'MaskType'));rb=normtext(getp(blocks{i},'ReferenceBlock'));
    cp=normtext(getp(blocks{i},'ComponentPath'));
    if contains(mt,'transformer')||contains(rb,'transformer')||contains(cp,'transformer') ...
            ||is_transformer_subsystem(blocks{i})
        transformers(end+1,1)=string(blocks{i}); %#ok<AGROW>
    end
end
transformers=unique(transformers,'stable');
end

function tf=is_discrete_six_diode_group(block)
tf=false;children=find_system(block,'SearchDepth',1,'LookUnderMasks','all', ...
    'FollowLinks','on','Type','Block');n=0;
for i=1:numel(children)
    if strcmp(children{i},block),continue;end
    mt=normtext(getp(children{i},'MaskType'));rb=normtext(getp(children{i},'ReferenceBlock'));
    cp=normtext(getp(children{i},'ComponentPath'));d=mt+"|"+rb+"|"+cp;
    trusted=contains(d,'diode')&&~contains(d,'igbt')&&~contains(d,'gto') ...
        &&~contains(d,'mosfet')&&~contains(d,'thyristor');
    n=n+double(trusted);
end
if n~=6,return;end
ph=[];try,ph=get_param(block,'PortHandles');catch,return;end
nL=0;nR=0;if isfield(ph,'LConn'),nL=numel(ph.LConn);end
if isfield(ph,'RConn'),nR=numel(ph.RConn);end
tf=(nL==3&&nR==2)||(nR==3&&nL==2)||(nL==1&&nR==2)||(nR==1&&nL==2);
end

function tf=is_transformer_subsystem(block)
tf=false;if ~strcmpi(getp(block,'BlockType'),'SubSystem'),return;end
ph=[];try,ph=get_param(block,'PortHandles');catch,return;end
n=0;for f={'LConn','RConn'},if isfield(ph,f{1}),n=n+numel(ph.(f{1}));end,end
if n<2,return;end
children=find_system(block,'SearchDepth',1,'LookUnderMasks','all', ...
    'FollowLinks','on','Type','Block');
for i=1:numel(children)
    if strcmp(children{i},block),continue;end
    d=normtext(getp(children{i},'MaskType'))+"|" ...
        +normtext(getp(children{i},'ReferenceBlock'))+"|" ...
        +normtext(getp(children{i},'ComponentPath'));
    if contains(d,'transformer')||contains(d,'mutual inductor'),tf=true;return;end
end
end

function ids=block_physical_nodes(G,block)
ids=find(string({G.nodes.network})=="physical"&string({G.nodes.block})==string(block));
end
function ids=sort_by_ordinal(G,ids)
if isempty(ids),return;end;[~,ix]=sort([G.nodes(ids).port_ordinal]);ids=ids(ix);
end
function p=restore_path(prev,hit)
p=hit;while prev(p(1))~=0,p=[prev(p(1)) p];end %#ok<AGROW>
end
function s=path_label(G,path)
parts=port_labels(G,path);s=strjoin(parts," -> ");
end
function out=port_labels(G,ids)
out=strings(numel(ids),1);for i=1:numel(ids),n=G.nodes(ids(i)); ...
        out(i)=n.block+"["+n.port_field+"#"+string(n.port_ordinal)+"]";end
end

function [value,valid]=scalar_logical(x)
valid=(islogical(x)||isnumeric(x))&&isscalar(x)&&isfinite(double(x));
if valid,value=logical(x);else,value=false;end
end
function rows=empty_groups()
rows=struct('bridge',{},'transformer',{},'phase_deg',{},'active',{}, ...
    'supply_path',{},'output_path',{},'source',{},'source_path',{}, ...
    'dc_combiner',{},'dc_combine_path',{},'load',{},'load_path',{}, ...
    'output_sensor',{},'ownership_resolved',{},'winding_port',{}, ...
    'phase_evidence',{});
end
function rows=empty_inventory()
rows=struct('bridge',{},'status',{},'ac_ports',{},'dc_ports',{}, ...
    'output_ok',{},'local_supply_ok',{},'phase_ok',{},'phase_deg',{}, ...
    'transformer',{},'winding_port',{},'supply_paths',{},'output_paths',{}, ...
    'source_ok',{},'source',{},'source_paths',{},'combine_ok',{}, ...
    'source_reason',{},'dc_combiner',{},'dc_combine_paths',{}, ...
    'combine_reason',{},'load_ok',{},'load',{}, ...
    'load_paths',{},'output_sensor',{},'output_sensor_paths',{}, ...
    'phase_evidence',{});
end
function r=inventory_row(bridge)
r=struct('bridge',string(bridge),'status',"UNINITIALIZED", ...
    'ac_ports',strings(0,1),'dc_ports',strings(0,1),'output_ok',false, ...
    'local_supply_ok',false,'phase_ok',false,'phase_deg',[], ...
    'transformer',"",'winding_port',"",'supply_paths',strings(0,1), ...
    'output_paths',strings(0,1),'source_ok',false,'source',"", ...
    'source_paths',strings(0,1),'combine_ok',false,'source_reason',"UNRESOLVED", ...
    'dc_combiner',"",'dc_combine_paths',strings(0,1), ...
    'combine_reason',"UNRESOLVED",'load_ok',false,'load',"", ...
    'load_paths',strings(0,1),'output_sensor',"", ...
    'output_sensor_paths',strings(0,1),'phase_evidence',struct());
end

function values=parse_angles(raw)
values=[];s=lower(char(raw));tokens=regexp(s,'([-+]?\d+(?:\.\d+)?)\s*deg','tokens');
if ~isempty(tokens),values=cellfun(@(x)str2double(x{1}),tokens);
elseif ~isempty(regexp(s,'delta\s*d11','once')),values=30;
elseif ~isempty(regexp(s,'delta\s*d1(?:\D|$)','once')),values=-30;
elseif ~isempty(regexp(strtrim(s),'^y(?:n|g)?$','once')),values=0;end
end
function nums=numeric_literals(raw)
t=regexp(char(raw),'[-+]?(?:\d*\.?\d+)(?:[eE][-+]?\d+)?','match');
if isempty(t),nums=[];else,nums=cellfun(@str2double,t);nums=nums(isfinite(nums));end
end
function cfg=find_check(spec,id)
cfg=[];if ~isfield(spec,'task_specific_checks'),return;end;x=spec.task_specific_checks;if ~iscell(x),x=num2cell(x);end
for i=1:numel(x),if isfield(x{i},'id')&&string(x{i}.id)==string(id),cfg=x{i};return;end,end
end
function v=ternary_reason(tf,a,b),if tf,v=string(a);else,v=string(b);end,end
function v=getnum(s,f,d),v=d;if isstruct(s)&&isfield(s,f)&&isnumeric(s.(f))&&isscalar(s.(f))&&isfinite(s.(f)),v=double(s.(f));end,end
function v=getp(block,param),v="";try,v=string(get_param(block,char(param)));catch,end,end
function v=normtext(x),v=lower(regexprep(string(x),'\s+',' '));end
function r=base_report(scenario)
r=struct('task',"D028",'id',"D028.active_phase_shift_branch_ownership", ...
    'kind',"task_specific",'semantic_kind',"structure",'scenario',string(scenario), ...
    'layer',"qualification",'evaluated',false,'mandatory',true,'ok',false, ...
    'valid',false,'score',0,'detail',"UNINITIALIZED",'evidence',struct());
end
