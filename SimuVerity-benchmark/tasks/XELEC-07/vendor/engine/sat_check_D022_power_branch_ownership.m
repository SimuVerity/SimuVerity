function report=sat_check_D022_power_branch_ownership( ...
    modelName,spec,scenarioId,simOut,signals,baseReports,state) %#ok<INUSD>
%SAT_CHECK_D022_POWER_BRANCH_OWNERSHIP Physical ownership of three powers.
% The three scalar powers must terminate at distinct native power blocks or
% verified Vabc/Iabc computations.  Their distinct physical sensor sets
% must either isolate the claimed physical branch or, for exact native
% inline current taps that are not graph cuts in grounded multi-conductor
% networks, form a unique one-to-one assignment to the source, public user
% load and converter-controlled ballast anchors.  Block names, drawing
% coordinates and controller form are not role evidence.

report=base_report(scenarioId);report.evaluated=true;
if ~isstruct(spec)||~isfield(spec,'id')||string(spec.id)~="D022" ...
        ||string(scenarioId)~="nominal"
    report.detail="TASK_OR_SCENARIO_IDENTITY_MISMATCH";return;
end
if isstruct(modelName)&&isfield(modelName,'schema') ...
        &&string(modelName.schema)=="D022.power-branch-fixture"
    report=evaluate_fixture(report,modelName);return;
end
try
    if isstruct(state)&&isfield(state,'model_graph')&&isstruct(state.model_graph) ...
            &&isfield(state.model_graph,'schema')
        G=state.model_graph;
    else
        G=sat_model_graph(modelName);
    end
    names=["Psource","Pload","Pdump"];
    endpoints=strings(1,3);sensorSets=cell(1,3);witnessKinds=strings(1,3);
    for i=1:3
        [w,ok,why]=power_witness(modelName,baseReports,names(i));
        if ~ok,report.detail=why;return;end
        endpoints(i)=w.endpoint;witnessKinds(i)=w.kind;
        if w.kind=="native_power_measurement"
            sensorSets{i}=upstream_current_sensors(G,endpoints(i));
        else
            sensorSets{i}=string(w.sensor_blocks(:));
        end
        if ~sensor_set_complete(G,sensorSets{i})
            report.detail=names(i)+"_THREE_PHASE_CURRENT_PROVENANCE_MISSING";return;
        end
    end
    [userBlocks,ok,why]=input_binding_blocks(baseReports,"R_user");
    if ~ok,report.detail=why;return;end
    % Consume the independent physical energy-path proof.  That proof owns
    % source/stage discovery and does not call this branch checker, so there
    % is no recursive dependency and no source name/regex path evidence.
    energy=sat_check_D022_energy_path_ownership( ...
        modelName,spec,scenarioId,simOut,signals,baseReports,state);
    if isempty(energy)||~energy.evaluated||~energy.valid||~energy.ok
        detail="MISSING";if ~isempty(energy)&&isfield(energy,'detail'),detail=string(energy.detail);end
        report.detail="ENERGY_PATH_OWNERSHIP_FAILED:"+detail;return;
    end
    if ~isfield(energy.evidence,'source_blocks') ...
            ||~isfield(energy.evidence,'ballast_converter_roots')
        report.detail="ENERGY_PATH_ROLE_ENDPOINTS_MISSING";return;
    end
    sourceBlocks=topmost(unique(string(energy.evidence.source_blocks(:)),'stable'));
    ballastBlocks=topmost(unique(string(energy.evidence.ballast_converter_roots(:)),'stable'));
    if isempty(sourceBlocks)||isempty(ballastBlocks)
        report.detail="ENERGY_PATH_ROLE_ENDPOINTS_EMPTY";return;
    end
    distinct=numel(unique(endpoints))==3;
    sensorSignatures=strings(1,3);
    for i=1:3,sensorSignatures(i)=strjoin(sort(string(sensorSets{i}(:))),"|");end
    sensorsDistinct=all(strlength(sensorSignatures)>0) ...
        &&numel(unique(sensorSignatures))==3;
    anchorPairConnectivity=[ ...
        physical_connected_without(G,sourceBlocks,userBlocks,[]), ...
        physical_connected_without(G,sourceBlocks,ballastBlocks,[]), ...
        physical_connected_without(G,userBlocks,ballastBlocks,[])];
    expectedCutConnectivity=logical([0 0 1;0 1 0;1 0 0]);
    cutPairConnectivity=false(3,3);
    % Distances to different kinds of anchors are not on a comparable
    % scale: an input-bound load can legitimately be nested deeper than a
    % source measurement.  Therefore a native current-tap fallback is a
    % one-to-one assignment question, not a row-wise "nearest anchor"
    % question.  For each claimed role, its sensor set must be the unique
    % closest candidate among all three independently witnessed powers.
    distances=Inf(3,3);
    for i=1:3
        distances(i,:)=[ ...
            physical_distance(G,sensorSets{i},sourceBlocks), ...
            physical_distance(G,sensorSets{i},userBlocks), ...
            physical_distance(G,sensorSets{i},ballastBlocks)];
    end
    anchorAssignment=false(1,3);anchorMargins=-Inf(1,3);
    for i=1:3
        claimed=distances(i,i);others=distances(setdiff(1:3,i),i);
        anchorAssignment(i)=isfinite(claimed)&&all(isfinite(others)) ...
            &&all(claimed<others);
        if isfinite(claimed)&&all(isfinite(others))
            anchorMargins(i)=min(others)-claimed;
        end
    end
    roles=repmat(struct('name',"",'endpoint',"",'current_sensors',strings(0,1), ...
        'distance_to_source',Inf,'distance_to_user',Inf, ...
        'distance_to_converter',Inf,'nearest_role',"", ...
        'nearest_unique',false,'cut_pair_connectivity',false(1,3), ...
        'cut_informative',false,'source_tap_fallback_allowed',false, ...
        'distance_role_match',false,'anchor_assignment_match',false, ...
        'anchor_assignment_margin',-Inf,'owned_role',"", ...
        'ownership_mode',"",'ownership_unique',false),1,3);
    for i=1:3
        ds=distances(i,1);du=distances(i,2);dc=distances(i,3);
        values=[ds du dc];[~,nearest]=min(values);ordered=sort(values);
        nearestUnique=ordered(1)<ordered(2);roleNames=["source","user","converter"];
        blocked=physical_nodes(G,sensorSets{i});
        cutPairConnectivity(i,:)=[ ...
            physical_connected_without(G,sourceBlocks,userBlocks,blocked), ...
            physical_connected_without(G,sourceBlocks,ballastBlocks,blocked), ...
            physical_connected_without(G,userBlocks,ballastBlocks,blocked)];
        cutInformative=~isequal(cutPairConnectivity(i,:),anchorPairConnectivity);
        cutOwned=isequal(cutPairConnectivity(i,:),expectedCutConnectivity(i,:));
        % Retain the old field as a compatibility alias, but its meaning is
        % now the representation-fair, column-wise role assignment below.
        distanceRoleMatch=anchorAssignment(i);
        fallbackAllowed=~cutInformative ...
            &&source_current_tap_fallback_allowed(G,witnessKinds(i),sensorSets{i});
        ownershipUnique=cutOwned||(fallbackAllowed&&distanceRoleMatch);
        if cutOwned,ownershipMode="branch_cut";
        elseif fallbackAllowed&&distanceRoleMatch,ownershipMode="native_tap_anchor_assignment";
        else,ownershipMode="unproven";end
        roles(i)=struct('name',names(i),'endpoint',endpoints(i), ...
            'current_sensors',sensorSets{i},'distance_to_source',ds, ...
            'distance_to_user',du,'distance_to_converter',dc, ...
            'nearest_role',roleNames(nearest),'nearest_unique',nearestUnique, ...
            'cut_pair_connectivity',cutPairConnectivity(i,:), ...
            'cut_informative',cutInformative, ...
            'source_tap_fallback_allowed',fallbackAllowed, ...
            'distance_role_match',distanceRoleMatch, ...
            'anchor_assignment_match',anchorAssignment(i), ...
            'anchor_assignment_margin',anchorMargins(i), ...
            'owned_role',roleNames(i), ...
            'ownership_mode',ownershipMode,'ownership_unique',ownershipUnique);
    end
    finiteRoles=all(isfinite(distances),'all');
    anchorsConnected=all(anchorPairConnectivity);
    roleOk=all([roles.ownership_unique]);
    report.valid=logical(distinct&&sensorsDistinct&&finiteRoles&&anchorsConnected);
    report.ok=logical(report.valid&&roleOk);report.score=double(report.ok);
    report.evidence=struct('power_endpoints',endpoints,'endpoints_distinct',distinct, ...
        'power_witness_kinds',witnessKinds,'power_sensor_sets',{sensorSets}, ...
        'power_sensor_sets_distinct',sensorsDistinct, ...
        'source_blocks',sourceBlocks,'user_blocks',userBlocks, ...
        'ballast_converter_blocks',ballastBlocks, ...
        'anchor_pair_order',["source-user","source-converter","user-converter"], ...
        'anchor_pair_connectivity',anchorPairConnectivity, ...
        'expected_cut_pair_connectivity',expectedCutConnectivity, ...
        'cut_pair_connectivity',cutPairConnectivity, ...
        'distance_matrix',distances, ...
        'anchor_assignment_match',anchorAssignment, ...
        'anchor_assignment_margin',anchorMargins,'roles',roles);
    if ~distinct,report.detail="POWER_MEASUREMENT_ENDPOINTS_NOT_DISTINCT";
    elseif ~sensorsDistinct,report.detail="POWER_MEASUREMENT_SENSORS_NOT_DISTINCT";
    elseif ~finiteRoles||~anchorsConnected,report.detail="ROLE_ENDPOINT_PHYSICAL_CONNECTIVITY_INVALID";
    elseif ~roleOk,report.detail="POWERS_NOT_OWNED_BY_SOURCE_USER_BALLAST_BRANCHES";
    else,report.detail="OK";end
catch ex
    report.valid=false;report.ok=false;report.score=0;
    report.detail="BRANCH_OWNERSHIP_EXTRACTION_ERROR:"+string(ex.identifier);
    report.evidence=struct('message',string(strtrim(ex.message)));
end
end

function report=evaluate_fixture(report,f)
required={'endpoints_distinct','anchor_pair_connectivity','cut_pair_connectivity', ...
    'distance_matrix','witness_kinds','source_current_tap_sets'};
if ~all(isfield(f,required)),report.detail="SEMANTIC_FIXTURE_SCHEMA_INVALID";return;end
anchorConnectivity=logical(f.anchor_pair_connectivity);
cutConnectivity=logical(f.cut_pair_connectivity);
validConnectivity=isequal(size(anchorConnectivity),[1 3]) ...
    &&isequal(size(cutConnectivity),[3 3]);
expected=logical([0 0 1;0 1 0;1 0 0]);
dist=double(f.distance_matrix);kinds=string(f.witness_kinds);
sourceTap=logical(f.source_current_tap_sets);
validDistance=isequal(size(dist),[3 3])&&all(isfinite(dist),'all');
validKinds=isequal(size(kinds),[1 3])&&isequal(size(sourceTap),[1 3]);
sensorDistinct=true;if isfield(f,'sensors_distinct'),sensorDistinct=logical(f.sensors_distinct);end
report.valid=logical(f.endpoints_distinct&&sensorDistinct&&validConnectivity ...
    &&validDistance&&validKinds&&all(anchorConnectivity));
owned=false(1,3);modes=strings(1,3);assignment=false(1,3);margins=-Inf(1,3);
for i=1:3
    claimed=dist(i,i);others=dist(setdiff(1:3,i),i);
    assignment(i)=isfinite(claimed)&&all(isfinite(others))&&all(claimed<others);
    if isfinite(claimed)&&all(isfinite(others)),margins(i)=min(others)-claimed;end
    cutInformative=~isequal(cutConnectivity(i,:),anchorConnectivity);
    cutOwned=isequal(cutConnectivity(i,:),expected(i,:));
    fallback=~cutInformative&&kinds(i)=="native_power_measurement"&&sourceTap(i);
    owned(i)=cutOwned||(fallback&&assignment(i));
    if cutOwned,modes(i)="branch_cut";
    elseif fallback&&assignment(i),modes(i)="native_tap_anchor_assignment";
    else,modes(i)="unproven";end
end
report.ok=logical(report.valid&&all(owned));
report.score=double(report.ok);report.evidence=f;
report.evidence.ownership_modes=modes;
report.evidence.anchor_assignment_match=assignment;
report.evidence.anchor_assignment_margin=margins;
if ~logical(f.endpoints_distinct),report.detail="POWER_MEASUREMENT_ENDPOINTS_NOT_DISTINCT";
elseif ~sensorDistinct,report.detail="POWER_MEASUREMENT_SENSORS_NOT_DISTINCT";
elseif ~validConnectivity||~all(anchorConnectivity),report.detail="ROLE_ENDPOINT_PHYSICAL_CONNECTIVITY_INVALID";
elseif ~report.ok,report.detail="POWERS_NOT_OWNED_BY_SOURCE_USER_BALLAST_BRANCHES";
else,report.detail="OK";end
end

function sensors=upstream_current_sensors(G,powerBlock)
targets=signal_nodes(G,powerBlock,"in");seen=reach(G.signal_reverse,targets,numel(G.nodes));
sensors=strings(0,1);
for i=find(seen)
    b=string(G.nodes(i).block);s=sat_provenance_semantic(char(b));
    if s.trusted&&s.kind=="measurement"&&contains(s.semantic,"current measurement")
        sensors(end+1,1)=b; %#ok<AGROW>
    end
end
sensors=topmost(unique(sensors,'stable'));
end

function [w,ok,reason]=power_witness(model,base,name)
w=struct();ok=false;reason=name+"_PHYSICAL_POWER_ENDPOINT_MISSING";
items=field_items(base,'output_reports');contractOk=false;
for i=1:numel(items)
    r=items{i};if ~isstruct(r)||~isfield(r,'name')||string(r.name)~=name ...
            ||~isfield(r,'ok')||~logical(r.ok)||~isfield(r,'provenance_ok') ...
            ||~logical(r.provenance_ok)||~isfield(r,'trace'),continue;end
    contractOk=true;break;
end
if ~contractOk,return;end
w=sat_d022_power_witness(model,name);
if w.ok,ok=true;reason="OK";else,reason=name+"_"+string(w.detail);end
end

function ok=sensor_set_complete(G,sensors)
sensors=unique(string(sensors(:)),'stable');ok=false;if isempty(sensors),return;end
threePhase=false(size(sensors));
for i=1:numel(sensors)
    s=sat_provenance_semantic(char(sensors(i)));
    threePhase(i)=s.trusted&&s.kind=="measurement" ...
        &&contains(s.semantic,"three-phase vi measurement") ...
        &&numel(physical_nodes(G,sensors(i)))>=6;
end
ok=any(threePhase)||numel(sensors)>=3;
end

function allowed=source_current_tap_fallback_allowed(G,witnessKind,sensors)
% Some source SPS native Power Measurement blocks obtain current from
% three one-port Current Measurement taps.  Those taps are observable but
% are not graph cuts.  Only that exact native representation may fall back
% to a unique physical-distance role; derived V-I computations must prove
% ownership by branch isolation.
allowed=string(witnessKind)=="native_power_measurement";
sensors=unique(string(sensors(:)),'stable');
if ~allowed||numel(sensors)~=3,allowed=false;return;end
for i=1:numel(sensors)
    s=sat_provenance_semantic(char(sensors(i)));
    if ~(s.trusted&&s.kind=="measurement" ...
            &&contains(s.semantic,"current measurement") ...
            &&~contains(s.semantic,"three-phase vi measurement"))
        allowed=false;return;
    end
    ids=physical_nodes(G,sensors(i));
    fields=string({G.nodes(ids).port_field});
    if numel(ids)~=2||~isequal(sort(lower(fields)),sort(["lconn","rconn"]))
        allowed=false;return;
    end
    % Each terminal must reach a physical node outside the sensor itself;
    % an internally connected but dangling decorative tap is not enough.
    for id=ids(:)'
        neighbors=G.physical_undirected{id};
        if ~any([G.nodes(neighbors).block]~=sensors(i))
            allowed=false;return;
        end
    end
end
end

function [blocks,ok,reason]=input_binding_blocks(base,name)
blocks=strings(0,1);ok=false;reason=name+"_PHYSICAL_BINDING_MISSING";
items=field_items(base,'input_reports');values=strings(0,1);
for i=1:numel(items)
    r=items{i};if isstruct(r)&&isfield(r,'name')&&string(r.name)==name ...
            &&isfield(r,'ok')&&logical(r.ok)&&isfield(r,'bindings')
        values=[values;string(r.bindings(:))]; %#ok<AGROW>
    end
end
for v=values(:)'
    p=split(v,"::");if numel(p)==2,blocks(end+1,1)=p(1);end %#ok<AGROW>
end
blocks=unique(blocks,'stable');ok=~isempty(blocks);if ok,reason="OK";end
end

function d=physical_distance(G,fromBlocks,toBlocks)
src=physical_nodes(G,fromBlocks);dst=physical_nodes(G,toBlocks);d=Inf;
if isempty(src)||isempty(dst),return;end
dist=Inf(1,numel(G.nodes));q=unique(src(:)');dist(q)=0;
while ~isempty(q)
    x=q(1);q(1)=[];
    if any(dst==x),d=dist(x);return;end
    for y=G.physical_undirected{x}
        if isinf(dist(y)),dist(y)=dist(x)+1;q(end+1)=y;end %#ok<AGROW>
    end
end
end
function connected=physical_connected_without(G,fromBlocks,toBlocks,blockedNodes)
src=physical_nodes(G,fromBlocks);dst=physical_nodes(G,toBlocks);
blocked=false(1,numel(G.nodes));
blockedNodes=double(blockedNodes(:)');
blockedNodes=blockedNodes(blockedNodes>=1&blockedNodes<=numel(G.nodes));
blocked(blockedNodes)=true;
src=src(~blocked(src));dst=dst(~blocked(dst));connected=false;
if isempty(src)||isempty(dst),return;end
seen=reach_blocked(G.physical_undirected,src,numel(G.nodes),blocked);
connected=any(seen(dst));
end
function ids=physical_nodes(G,blocks)
ids=[];for b=string(blocks(:))',ids=[ids find([G.nodes.block]==b ...
        &[G.nodes.network]=="physical")];end;ids=unique(ids); %#ok<AGROW>
end
function ids=signal_nodes(G,block,kind)
ids=find([G.nodes.block]==string(block)&[G.nodes.network]=="signal");
fields=lower(string({G.nodes(ids).port_field}));
if kind=="in",ids=ids(contains(fields,"in"));else,ids=ids(contains(fields,"out"));end
end
function seen=reach(adj,start,n)
seen=reach_blocked(adj,start,n,false(1,n));
end
function seen=reach_blocked(adj,start,n,blocked)
seen=false(1,n);q=unique(double(start(:)'));q=q(q>=1&q<=n&~blocked(q));seen(q)=true;
while ~isempty(q)
    x=q(1);q(1)=[];
    for y=adj{x},if ~blocked(y)&&~seen(y),seen(y)=true;q(end+1)=y;end,end %#ok<AGROW>
end
end
function out=topmost(blocks)
blocks=string(blocks(:));out=strings(0,1);
for i=1:numel(blocks)
    child=false;for j=1:numel(blocks)
        if i~=j&&startsWith(blocks(i),blocks(j)+"/"),child=true;break;end
    end
    if ~child,out(end+1,1)=blocks(i);end %#ok<AGROW>
end
end
function items=field_items(s,name)
if ~isstruct(s)||~isfield(s,name)||isempty(s.(name)),items={};
elseif iscell(s.(name)),items=s.(name)(:).';
else,items=arrayfun(@(x)x,s.(name),'UniformOutput',false);end
end
function r=base_report(scenario)
r=struct('task',"D022",'id',"D022.power_branch_ownership", ...
    'kind',"task_specific",'semantic_kind',"structure",'scenario',string(scenario), ...
    'layer',"qualification",'evaluated',false,'mandatory',true,'ok',false, ...
    'valid',false,'score',0,'detail',"UNINITIALIZED",'evidence',struct());
end
