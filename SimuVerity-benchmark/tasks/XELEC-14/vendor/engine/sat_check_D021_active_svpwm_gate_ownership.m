function report=sat_check_D021_active_svpwm_gate_ownership( ...
    modelName,spec,scenarioId,simOut,signals,baseReports,state) %#ok<INUSD>
%SAT_CHECK_D021_ACTIVE_SVPWM_GATE_OWNERSHIP
% Source function/report identifier retained for public report compatibility.
% The predicate is now modulation-independent: it proves that a real
% three-level NPC power stage has live command lineage, without requiring
% SVPWM, a T-type converter, a named sector selector, or a particular PWM.

if string(scenarioId)~="nominal",report=struct([]);return;end
report=base_report(scenarioId);report.evaluated=true;
[baseOk,baseRows]=required_base_reports(baseReports, ...
    ["three_phase_npc_stage","split_dc_storage", ...
     "dc_to_load_power_path"]);
try
    if isstruct(modelName)&&isfield(modelName,'schema') ...
            &&string(modelName.schema)=="D021.semantic-fixture"
        facts=modelName;
    else
        facts=extract_facts(modelName);
    end
catch ex
    report.detail="FACT_EXTRACTION_FAILED:"+string(ex.identifier);
    report.evidence=struct('base_reports',baseRows,'message',string(ex.message));
    return;
end

counts=double(facts.switch_counts(:));
clamps=double(getfield_default(facts,'clamping_counts',zeros(size(counts)))); %#ok<GFLD>
coverage=double(getfield_default(facts,'gate_coverage_counts',zeros(size(counts)))); %#ok<GFLD>
activeClampPaths=double(getfield_default(facts,'active_clamping_path_counts',zeros(size(counts)))); %#ok<GFLD>
activeClampTopology=getfield_default(facts,'active_clamping_topology',struct([])); %#ok<GFLD>
diodeClamped=counts>=12&clamps>=6&coverage>=counts;
activeClamped=counts>=12&activeClampPaths>=3&coverage>=counts;
stageOk=diodeClamped|activeClamped;
packaged=double(getfield_default(facts,'packaged_live_stage_count',0))>=1; %#ok<GFLD>
hasDiscrete=any(stageOk);
report.valid=logical(baseOk&&(hasDiscrete||packaged));
report.ok=report.valid;report.score=double(report.ok);
report.evidence=struct('base_reports',baseRows, ...
    'candidate_stages',string(facts.converter_blocks), ...
    'controllable_switch_counts',counts, ...
    'dedicated_clamping_diode_counts',clamps, ...
    'active_clamping_path_counts',activeClampPaths, ...
    'active_clamping_topology',{activeClampTopology}, ...
    'diode_clamped_stage_mask',logical(diodeClamped), ...
    'active_clamped_stage_mask',logical(activeClamped), ...
    'gate_coverage_counts',coverage,'stage_pass_mask',logical(stageOk), ...
    'packaged_live_stage_count',double(getfield_default(facts,'packaged_live_stage_count',0)), ... %#ok<GFLD>
    'gate_lineage_blocks',string(facts.gate_lineage_blocks), ...
    'gate_lineage_descriptors',string(facts.gate_lineage_descriptors), ...
    'algorithm_constraint',"none");
if ~baseOk,report.detail="D021_BASE_NPC_CONTRACT_FAILED";
elseif ~(hasDiscrete||packaged),report.detail="ACTIVE_NPC_COMMAND_LINEAGE_NOT_PROVEN";
else,report.detail="OK";end
end

function facts=extract_facts(model)
name=char(string(model));assert(~isempty(name)&&bdIsLoaded(name),'SimuVerity:D021:ModelNotLoaded');
blocks=string(find_system(name,'LookUnderMasks','all','FollowLinks','on','Type','Block'));
parents=strings(0,1);cells=strings(0,1);cellLive=false(0,1);
lineageBlocks=strings(0,1);lineageDesc=strings(0,1);counts=[];clamps=[];coverage=[];activeClampPaths=[];
activeClampTopology={};
packagedLive=0;
for b=blocks(:)'
    d=descriptor(char(b));
    if is_controllable_cell(d)
        p=string(getp(char(b),'Parent'));parents(end+1,1)=p;cells(end+1,1)=b; %#ok<AGROW>
        ph=[];try,ph=get_param(char(b),'PortHandles');catch,end
        live=false;
        if isstruct(ph)&&isfield(ph,'Inport')
            [up,~]=trace_upstream(ph.Inport,name,20000);
            lineageBlocks=[lineageBlocks;up(:)]; %#ok<AGROW>
            live=has_dynamic_source(up);
        end
        cellLive(end+1,1)=logical(live); %#ok<AGROW>
    elseif is_trusted_packaged_npc(char(b)) ...
            &&has_physical_and_signal_ports(char(b))
        ph=get_param(char(b),'PortHandles');[up,~]=trace_upstream(ph.Inport,name,20000);
        lineageBlocks=[lineageBlocks;up(:)]; %#ok<AGROW>
        packagedLive=packagedLive+double(has_dynamic_source(up));
    end
end
u=unique(parents,'stable');stageBlocks=strings(0,1);
for p=u(:)'
    ix=find(parents==p);n=numel(ix);if n<12,continue;end
    stageBlocks(end+1,1)=p;counts(end+1)=n;coverage(end+1)=sum(cellLive(ix)); %#ok<AGROW>
    clamps(end+1)=direct_pure_diode_count(char(p)); %#ok<AGROW>
    [activeClampPaths(end+1),activeClampTopology{end+1}]= ...
        active_clamp_path_count(char(p),cells(ix)); %#ok<AGROW>
end
lineageBlocks=unique(lineageBlocks,'stable');
for b=lineageBlocks(:)',lineageDesc(end+1,1)=descriptor(char(b));end %#ok<AGROW>
facts=struct('schema',"D021.production-facts", ...
    'converter_blocks',stageBlocks,'switch_counts',counts, ...
    'clamping_counts',clamps,'gate_coverage_counts',coverage, ...
    'active_clamping_path_counts',activeClampPaths, ...
    'active_clamping_topology',{activeClampTopology}, ...
    'packaged_live_stage_count',packagedLive, ...
    'gate_lineage_blocks',lineageBlocks, ...
    'gate_lineage_descriptors',lineageDesc);
end

function tf=has_physical_and_signal_ports(block)
tf=false;ph=[];try,ph=get_param(block,'PortHandles');catch,return;end
nphys=0;for f={'LConn','RConn'},if isfield(ph,f{1}),nphys=nphys+numel(ph.(f{1}));end,end
tf=nphys>=3&&isfield(ph,'Inport')&&~isempty(ph.Inport);
end
function tf=is_controllable_cell(d)
tf=~isempty(regexpi(char(d),'igbt|mosfet|\bgto\b|ideal switch','once')) ...
    &&isempty(regexpi(char(d),'universal bridge','once'));
end
function tf=is_trusted_packaged_npc(block)
d=lower(strjoin(string({getp(block,'MaskType'),getp(block,'ReferenceBlock'), ...
    getp(block,'ComponentPath')}),"|"));
tf=~isempty(regexpi(char(d),'neutral.?point.?clamp|diode.?clamp|\bnpc\b','once'));
end
function n=direct_pure_diode_count(parent)
n=0;kids=find_system(parent,'SearchDepth',1,'LookUnderMasks','all', ...
    'FollowLinks','on','Type','Block');
for i=1:numel(kids)
    if strcmp(kids{i},parent),continue;end
    d=lower(strjoin(string({getp(kids{i},'MaskType'),getp(kids{i},'ReferenceBlock'), ...
        getp(kids{i},'ComponentPath')}),"|"));
    pure=~isempty(regexpi(char(d),'(^|[/|])diode([/|]|$)|^diode$','once')) ...
        &&isempty(regexpi(char(d),'igbt|mosfet|gto|thyristor','once'));
    n=n+double(pure);
end
end

function [n,diag]=active_clamp_path_count(stage,cells)
% Prove an implementation-neutral active-clamped three-level motif.  The
% two DC-link capacitors identify positive rail, neutral midpoint and
% negative rail.  A valid stage has three distinct phase junctions that
% each connect to both outer rails through controllable cells, and each is
% also reachable from the neutral midpoint through a controllable clamp
% branch.  No block, modulation, or T-type role name is consulted.
n=0;roots=stage_line_roots(stage);switchEdges=zeros(0,2);
for b=string(cells(:))'
    e=physical_block_edge(roots,b);
    if numel(e)==2,switchEdges(end+1,:)=e;end %#ok<AGROW>
end
switchEdges=unique(sort(switchEdges,2),'rows','stable');
diag=struct('switch_edges',switchEdges,'capacitor_edges',zeros(0,2), ...
    'candidate_midpoints',[],'candidate_phase_counts',[],'proved_path_counts',[], ...
    'qualifying_component_edge_counts',{{}},'covered_active_cell_counts',[]);
if size(switchEdges,1)<9,return;end

kids=find_system(stage,'SearchDepth',1,'LookUnderMasks','all', ...
    'FollowLinks','on','Type','Block');capEdges=zeros(0,2);
for i=1:numel(kids)
    if strcmp(kids{i},stage)||~is_capacitor(kids{i}),continue;end
    e=physical_block_edge(roots,string(kids{i}));
    if numel(e)==2,capEdges(end+1,:)=e;end %#ok<AGROW>
end
capEdges=unique(sort(capEdges,2),'rows','stable');
diag.capacitor_edges=capEdges;
if size(capEdges,1)<2,return;end

nodes=unique(capEdges(:))';
for midpoint=nodes
    incident=find(any(capEdges==midpoint,2));
    if numel(incident)<2,continue;end
    rails=[];
    for q=incident(:)'
        rails(end+1)=capEdges(q,capEdges(q,:)~=midpoint); %#ok<AGROW>
    end
    rails=unique(rails,'stable');if numel(rails)~=2,continue;end
    [proved,componentCount,edgeCounts,covered]= ...
        active_phase_components(switchEdges,[rails midpoint]);
    diag.candidate_midpoints(end+1)=midpoint; %#ok<AGROW>
    diag.candidate_phase_counts(end+1)=componentCount; %#ok<AGROW>
    diag.proved_path_counts(end+1)=proved; %#ok<AGROW>
    diag.qualifying_component_edge_counts{end+1}=edgeCounts; %#ok<AGROW>
    diag.covered_active_cell_counts(end+1)=covered; %#ok<AGROW>
    n=max(n,proved);
end
end

function [proved,componentCount,edgeCounts,covered]=active_phase_components(edges,buses)
% Remove the positive, neutral and negative DC buses, then identify
% independent controllable-switch components.  A valid active-clamped
% phase component must connect back to all three buses and contain at least
% four distinct cells.  This admits T-type, ANPC and deeper equivalent
% hierarchies without requiring one named/common phase junction.
proved=0;componentCount=0;edgeCounts=[];covered=0;
nodes=setdiff(unique(edges(:))',buses,'stable');seen=[];components={};
for start=nodes
    if any(seen==start),continue;end
    comp=start;queue=start;seen(end+1)=start; %#ok<AGROW>
    while ~isempty(queue)
        x=queue(1);queue(1)=[];
        linked=[];
        for i=1:size(edges,1)
            if any(buses==edges(i,1))||any(buses==edges(i,2)),continue;end
            if edges(i,1)==x,linked(end+1)=edges(i,2); %#ok<AGROW>
            elseif edges(i,2)==x,linked(end+1)=edges(i,1);end %#ok<AGROW>
        end
        linked=setdiff(unique(linked,'stable'),seen,'stable');
        seen=[seen linked];comp=[comp linked];queue=[queue linked]; %#ok<AGROW>
    end
    components{end+1}=unique(comp,'stable'); %#ok<AGROW>
end
componentCount=numel(components);coveredRows=[];
for q=1:numel(components)
    comp=components{q};touch=false(1,3);owned=[];
    for i=1:size(edges,1)
        in1=any(comp==edges(i,1));in2=any(comp==edges(i,2));
        if ~(in1||in2),continue;end
        other=edges(i,1);if in1,other=edges(i,2);end
        if ~in1&&in2,other=edges(i,1);end
        if any(comp==other)||any(buses==other),owned(end+1)=i;end %#ok<AGROW>
        for b=1:3,touch(b)=touch(b)||((in1&&edges(i,2)==buses(b)) ...
                ||(in2&&edges(i,1)==buses(b)));end
    end
    owned=unique(owned,'stable');
    if all(touch)&&numel(owned)>=4
        proved=proved+1;edgeCounts(end+1)=numel(owned); %#ok<AGROW>
        coveredRows=[coveredRows owned]; %#ok<AGROW>
    end
end
covered=numel(unique(coveredRows));
if proved<3||covered<12,proved=0;end
end

function roots=stage_line_roots(stage)
% Use only native Simulink line families and exact PortConnectivity handles.
% Coincident or crossing drawing geometry is never electrical evidence.
ports=[];
stageBlocks=find_system(stage,'SearchDepth',1,'LookUnderMasks','all', ...
    'FollowLinks','on','Type','Block');
for i=1:numel(stageBlocks)
    ph=[];try,ph=get_param(stageBlocks{i},'PortHandles');catch,end
    if ~isstruct(ph),continue;end
    for f={'LConn','RConn'}
        if ~isfield(ph,f{1}),continue;end
        ports=[ports double(ph.(f{1})(:))']; %#ok<AGROW>
    end
end
[roots,~]=sat_native_physical_line_nets(stage,ports);
end
function e=physical_block_edge(roots,block)
ph=[];try,ph=get_param(char(block),'PortHandles');catch,end;lines=[];
if isstruct(ph),for f={'LConn','RConn'}
    if ~isfield(ph,f{1}),continue;end
    for h=double(ph.(f{1})(:))'
        lh=-1;try,lh=double(get_param(h,'Line'));catch,end
        k=line_key(lh);if lh>0&&isKey(roots,k),lines(end+1)=roots(k);end %#ok<AGROW>
    end
end,end
e=unique(lines,'stable');if numel(e)~=2,e=[];end
end
function k=line_key(h),k=sprintf('%.15g',double(h));end
function tf=is_capacitor(block)
d=lower(strjoin(string({getp(block,'Name'),getp(block,'MaskType'), ...
    getp(block,'ReferenceBlock'),getp(block,'ComponentPath')}),"|"));
branch=upper(strtrim(string(getp(block,'BranchType'))));
tf=branch=="C"||~isempty(regexpi(char(d),'(^|[/| _-])capacitor([/| _-]|$)','once'));
end
function tf=has_dynamic_source(blocks)
tf=false;
for b=string(blocks(:))'
    d=descriptor(char(b));
    inert=~isempty(regexpi(char(d),'\|constant\||\|ground\||\|terminator\||\|from\||\|goto\||\|inport\||\|outport\||\|mux\||\|demux\||\|bus selector\||\|bus creator\|','once'));
    if ~inert,tf=true;return;end
end
end

function [blocks,kinds]=trace_upstream(startPorts,model,maxVisits)
queue=double(startPorts(:)');seen=[];blocks=strings(0,1);kinds=strings(0,1);visits=0;
while ~isempty(queue)&&visits<maxVisits
    p=queue(1);queue(1)=[];if p<=0||any(seen==p),continue;end
    seen(end+1)=p;visits=visits+1; %#ok<AGROW>
    line=-1;try,line=get_param(p,'Line');catch,end
    if isempty(line)||line<0,continue;end
    src=get_param(line,'SrcPortHandle');if isempty(src)||src<0,continue;end
    b=string(get_param(src,'Parent'));blocks(end+1,1)=b;kinds(end+1,1)="signal_line"; %#ok<AGROW>
    ph=get_param(char(b),'PortHandles');bt=string(getp(char(b),'BlockType'));
    if bt=="From"
        tag=getp(char(b),'GotoTag');hits=find_system(model,'LookUnderMasks','all', ...
            'FollowLinks','on','BlockType','Goto','GotoTag',tag);
        if numel(hits)==1,gp=get_param(hits{1},'PortHandles');queue=[queue double(gp.Inport(:)')];end %#ok<AGROW>
    elseif bt=="Inport"
        parent=getp(char(b),'Parent');port=str2double(getp(char(b),'Port'));
        if ~isempty(parent)&&isfinite(port)&&port>=1&&~strcmp(parent,model)
            pph=[];try,pph=get_param(parent,'PortHandles');catch,end
            if isstruct(pph)&&isfield(pph,'Inport')&&numel(pph.Inport)>=port
                queue=[queue double(pph.Inport(port))]; %#ok<AGROW>
            end
        end
    elseif isfield(ph,'Inport')
        queue=[queue double(ph.Inport(:)')]; %#ok<AGROW>
    end
end
blocks=unique(blocks,'stable');kinds=unique(kinds,'stable');
end
function d=descriptor(block)
d=lower(strjoin(string({block,getp(block,'Name'),getp(block,'BlockType'), ...
    getp(block,'MaskType'),getp(block,'ReferenceBlock'),getp(block,'ComponentPath')}),"|"));
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
function v=getfield_default(s,f,d),if isfield(s,f),v=s.(f);else,v=d;end,end
function v=getp(b,p),v='';try,v=get_param(b,p);catch,end,end
function r=base_report(s)
r=struct('task',"D021",'id',"D021.active_svpwm_gate_ownership", ...
    'kind',"task_specific",'semantic_kind',"structure",'scenario',string(s), ...
    'layer',"qualification",'evaluated',false,'mandatory',true,'ok',false, ...
    'valid',false,'score',0,'detail',"UNINITIALIZED",'evidence',struct());
end
