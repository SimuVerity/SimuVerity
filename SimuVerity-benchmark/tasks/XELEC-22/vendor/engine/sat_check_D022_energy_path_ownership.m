function report=sat_check_D022_energy_path_ownership( ...
    modelName,spec,scenarioId,simOut,signals,baseReports,state) %#ok<INUSD>
%SAT_CHECK_D022_ENERGY_PATH_OWNERSHIP Physical AC/DC energy ownership.
% The source anchor comes from the evaluator-validated physical Psource
% branch, never a candidate block name.  Both terminals of the physically
% measured Vdc bus must be reached from that anchor through a MathWorks
% linked, live-controlled power device.  Ordinary Simulink signal coupling
% never enters the conserving-port proof; drawing coordinates are ignored.

if string(scenarioId)~="nominal",report=struct([]);return;end
if ~isstruct(spec)||~isscalar(spec)||~isfield(spec,'id')||string(spec.id)~="D022"
    report=make_report(false,false,false,"TASK_IDENTITY_MISMATCH",struct());return;
end
if has_fixture(state)
    facts=state.evidence.unit_test_energy_path_facts;
elseif isstruct(modelName)
    % Compatibility with older D022 semantic fixtures that do not represent
    % a loaded model or the new energy-path fact schema.
    report=struct([]);return;
else
    try,[facts,valid,reason]=extract_facts(modelName,baseReports,state);
    catch ex
        report=make_report(true,false,false, ...
            "ENERGY_PATH_EXTRACTION_ERROR:"+string(ex.identifier), ...
            struct('message',string(strtrim(ex.message))));return;
    end
    if ~valid,report=make_report(true,false,false,reason,facts);return;end
end
[valid,ok,detail]=verdict(facts);
report=make_report(true,valid,ok,detail,facts);
end

function [facts,valid,reason]=extract_facts(model,base,state)
facts=empty_facts();valid=false;reason="";G=task_graph(model,state);

% Psource has already passed the public output/provenance contract.  Its
% exact MathWorks physical measurement set is therefore the authoritative
% generator/PCC branch boundary even for a legal custom generator model.
[source,sourceKind,why]=source_anchor(G,model,base);
facts.source_blocks=source;facts.source_anchor_kind=sourceKind;
if isempty(source),reason=why;return;end

[sensor,why]=vdc_measurement(G,base);facts.vdc_measurement_block=sensor;
if strlength(sensor)==0,reason=why;return;end
rails=physical_nodes(G,sensor);facts.vdc_terminal_count=numel(rails);
if numel(rails)~=2,valid=true;reason="OK";return;end
facts.dc_rails_distinct=~same_native_net(G,rails(1),rails(2));

[controlled,controlRows]=controlled_power_blocks(G);
facts.controlled_power_blocks=controlled;facts.control_interfaces=controlRows;
if isempty(controlled),reason="LIVE_CONTROLLED_POWER_STAGE_UNRESOLVED";return;end
sources=physical_nodes(G,source);
if isempty(sources),reason="GENERATOR_PCC_PHYSICAL_ENDPOINT_UNRESOLVED";return;end

facts.rail_paths_owned=false(1,2);facts.rail_physical_paths=cell(1,2);
facts.rail_conversion_blocks=cell(1,2);
for i=1:2
    [hit,path,conversion]=controlled_path( ...
        G,sources,rails(i),rails(3-i),controlled);
    facts.rail_paths_owned(i)=hit;facts.rail_physical_paths{i}=path;
    facts.rail_conversion_blocks{i}=conversion;
end
facts.physical_energy_path_count=sum(facts.rail_paths_owned);
stageBlocks=unique([string(facts.rail_conversion_blocks{1}(:)); ...
    string(facts.rail_conversion_blocks{2}(:))],'stable');
facts.ballast_converter_roots=stage_roots(G,stageBlocks);
facts.same_ballast_stage=all(facts.rail_paths_owned) ...
    &&~isempty(facts.ballast_converter_roots) ...
    &&all(blocks_owned_by_roots(stageBlocks,facts.ballast_converter_roots));
facts.ac_dc_signal_only=false;facts.algorithm_constraint="none";
valid=true;reason="OK";
end

function [schemaOk,ok,detail]=verdict(f)
required={'source_blocks','source_anchor_kind','ballast_converter_roots', ...
    'controlled_power_blocks','vdc_measurement_block','vdc_terminal_count', ...
    'dc_rails_distinct','rail_paths_owned','rail_conversion_blocks', ...
    'same_ballast_stage','physical_energy_path_count','ac_dc_signal_only', ...
    'algorithm_constraint'};
schemaOk=isstruct(f)&&isscalar(f)&&all(isfield(f,required));
if ~schemaOk,ok=false;detail="FACT_SCHEMA_INVALID";return;end
paths=logical(f.rail_paths_owned);conversion=f.rail_conversion_blocks;
conversionComplete=iscell(conversion)&&numel(conversion)==2 ...
    &&all(cellfun(@(x)~isempty(string(x)),conversion));
shapeOk=isequal(size(paths),[1 2])&&isscalar(f.vdc_terminal_count) ...
    &&isfinite(double(f.vdc_terminal_count));
ok=shapeOk&&~isempty(f.source_blocks)&&strlength(string(f.source_anchor_kind))>0 ...
    &&~isempty(f.controlled_power_blocks) ...
    &&strlength(string(f.vdc_measurement_block))>0 ...
    &&double(f.vdc_terminal_count)==2&&logical(f.dc_rails_distinct) ...
    &&all(paths)&&conversionComplete&&~isempty(f.ballast_converter_roots) ...
    &&logical(f.same_ballast_stage) ...
    &&double(f.physical_energy_path_count)==2 ...
    &&~logical(f.ac_dc_signal_only);
if ok,detail="OK";
elseif ~shapeOk,detail="ENERGY_PATH_FACT_SHAPE_INVALID";
elseif isempty(f.source_blocks),detail="GENERATOR_PCC_PHYSICAL_ENDPOINT_UNRESOLVED";
elseif isempty(f.controlled_power_blocks),detail="LIVE_CONTROLLED_POWER_STAGE_UNRESOLVED";
elseif strlength(string(f.vdc_measurement_block))==0,detail="VDC_PHYSICAL_MEASUREMENT_UNRESOLVED";
elseif double(f.vdc_terminal_count)~=2,detail="VDC_MEASUREMENT_TERMINALS_NOT_UNIQUE";
elseif ~logical(f.dc_rails_distinct),detail="VDC_MEASUREMENT_DOES_NOT_SPAN_DISTINCT_RAILS";
elseif logical(f.ac_dc_signal_only)||~all(paths),detail="AC_DC_PHYSICAL_ENERGY_PATH_MISSING";
elseif ~conversionComplete,detail="LIVE_CONTROLLED_CONVERSION_MISSING_ON_ENERGY_PATH";
else,detail="VDC_RAILS_NOT_OWNED_BY_SAME_CONTROLLED_POWER_STAGE";end
end

function [blocks,kind,reason]=source_anchor(G,model,base)
blocks=strings(0,1);kind="";reason="PSOURCE_PHYSICAL_BRANCH_UNRESOLVED";
if ~output_contract_ok(base,"Psource"),return;end
w=sat_d022_power_witness(model,"Psource");if ~isstruct(w)||~w.ok,return;end
if string(w.kind)=="native_power_measurement"
    blocks=upstream_current_sensors(G,string(w.endpoint));
else
    blocks=string(w.sensor_blocks(:));
end
blocks=topmost(unique(blocks(strlength(blocks)>0),'stable'));
if isempty(blocks)||isempty(physical_nodes(G,blocks)),blocks=strings(0,1);return;end
kind="validated_Psource_physical_branch";reason="OK";
end

function tf=output_contract_ok(base,name)
tf=false;items=field_items(base,'output_reports');
for i=1:numel(items)
    r=items{i};if isstruct(r)&&isfield(r,'name')&&string(r.name)==string(name) ...
            &&logical_field(r,'ok')&&logical_field(r,'provenance_ok')
        tf=true;return;
    end
end
end

function sensors=upstream_current_sensors(G,powerBlock)
targets=signal_nodes(G,powerBlock,"in");seen=graph_reach(G.signal_reverse,targets,numel(G.nodes));
sensors=strings(0,1);
for i=find(seen)
    b=string(G.nodes(i).block);s=sat_provenance_semantic(char(b));
    if s.trusted&&s.kind=="measurement"&&contains(s.semantic,"current measurement")
        sensors(end+1,1)=b; %#ok<AGROW>
    end
end
sensors=topmost(unique(sensors,'stable'));
end

function [blocks,rows]=controlled_power_blocks(G)
blocks=strings(0,1);rows=struct('block',{},'control_input_nodes',{}, ...
    'upstream_control_nodes',{},'physical_internal_edge',{});
all=unique(string({G.nodes.block}),'stable');
for b=all(:)'
    if ~trusted_controlled_device(b),continue;end
    phys=physical_nodes(G,b);if numel(phys)<2,continue;end
    internal=has_internal_physical_edge(G,b,phys);if ~internal,continue;end
    gates=signal_nodes(G,b,"in");upstream=[];
    for g=gates(:)',upstream=[upstream G.signal_reverse{g}];end %#ok<AGROW>
    upstream=unique(upstream);upstream=upstream(string({G.nodes(upstream).block})~=b);
    if isempty(gates)||isempty(upstream),continue;end
    blocks(end+1,1)=b;rows(end+1)=struct('block',b, ... %#ok<AGROW>
        'control_input_nodes',double(gates),'upstream_control_nodes',double(upstream), ...
        'physical_internal_edge',true);
end
keep=true(size(blocks));
for i=1:numel(blocks)
    keep(i)=~any(startsWith(blocks(i),blocks((1:numel(blocks))~=i)+"/"));
end
blocks=blocks(keep);rows=rows(keep);
end

function tf=trusted_controlled_device(block)
% Trust installed MathWorks library identity plus a real control input.
% User-visible Name is deliberately absent from this descriptor.
bt=lower(string(getp(block,'BlockType')));mt=lower(string(getp(block,'MaskType')));
rb=lower(replace(string(getp(block,'ReferenceBlock')),"\\","/"));
dev=lower(string(getp(block,'Device')));link=lower(string(getp(block,'LinkStatus')));
library=any(link==["resolved","implicit"]) ...
    &&(startsWith(rb,"sps")||startsWith(rb,"ee_lib/")||startsWith(rb,"fl_lib/"));
d="|"+strjoin([bt mt rb dev],"|")+"|";
reject=["controlled current source","controlled voltage source", ...
    "current source","voltage source","machine","generator", ...
    "measurement","sensor"];
devices=["mosfet","igbt","gto","thyristor","ideal switch", ...
    "universal bridge","three-level bridge","power electronic converter"];
tf=library&&~any(contains(d,reject))&&any(contains(d,devices));
end

function tf=has_internal_physical_edge(G,block,ids)
tf=false;ids=double(ids(:)');
for u=ids
    neighbours=G.physical_undirected{u};kinds=string(G.physical_edge_kinds{u});
    for k=1:numel(neighbours)
        v=neighbours(k);
        if kinds(k)=="component_internal"&&any(ids==v) ...
                &&string(G.nodes(v).block)==string(block),tf=true;return;end
    end
end
end

function [hit,path,conversion]=controlled_path(G,start,target,blocked,controlled)
n=numel(G.nodes);seen=false(n,2);prev=zeros(n,2);prevState=zeros(n,2);
prevConversion=repmat("",n,2);q=zeros(0,2);
start=unique(double(start(:)'));start=start(start>=1&start<=n&start~=blocked);
for s=start,seen(s,1)=true;q(end+1,:)=[s 0];end %#ok<AGROW>
goal=[];
while ~isempty(q)
    row=q(1,:);q(1,:)=[];u=row(1);used=logical(row(2));
    if u==target&&used,goal=row;break;end
    neighbours=G.physical_undirected{u};kinds=G.physical_edge_kinds{u};
    for k=1:numel(neighbours)
        v=neighbours(k);if v==blocked,continue;end
        block=controlled_edge_block(G,u,v,string(kinds{k}),controlled);
        usedNext=used||strlength(block)>0;col=double(usedNext)+1;
        if seen(v,col),continue;end
        seen(v,col)=true;prev(v,col)=u;prevState(v,col)=double(used)+1;
        prevConversion(v,col)=block;q(end+1,:)=[v double(usedNext)]; %#ok<AGROW>
    end
end
hit=~isempty(goal);path=strings(0,1);conversion=strings(0,1);if ~hit,return;end
u=goal(1);col=2;path=string(G.nodes(u).block);
while prev(u,col)~=0
    if strlength(prevConversion(u,col))>0
        conversion=[prevConversion(u,col);conversion]; %#ok<AGROW>
    end
    old=u;u=prev(old,col);col=prevState(old,col);
    path=[string(G.nodes(u).block);path]; %#ok<AGROW>
end
path=unique(path,'stable');conversion=unique(conversion,'stable');
end

function block=controlled_edge_block(G,a,b,kind,controlled)
block="";if kind~="component_internal",return;end
ba=string(G.nodes(a).block);bb=string(G.nodes(b).block);
if ba==bb&&any(ba==controlled),block=ba;end
end

function roots=stage_roots(G,blocks)
blocks=unique(string(blocks(:)),'stable');roots=strings(0,1);if isempty(blocks),return;end
% Prefer the nearest shared subsystem that exposes both physical terminals
% and a signal control interface.  This covers hierarchical bridges.  A
% flat switch implementation remains legal and is represented by its set
% of trusted controlled device blocks.
parts=cellfun(@(x)split(string(x),"/"),cellstr(blocks),'UniformOutput',false);
limit=min(cellfun(@numel,parts));prefix=strings(0,1);
for k=1:limit
    token=parts{1}(1:k);candidate=strjoin(token,"/");
    if all(cellfun(@(x)startsWith(string(x),candidate),cellstr(blocks)))
        prefix(end+1,1)=candidate; %#ok<AGROW>
    else,break;end
end
for candidate=flip(prefix(:))'
    if candidate==string(G.model),continue;end
    if numel(physical_nodes(G,candidate))>=2&&~isempty(signal_nodes(G,candidate,"in"))
        roots=candidate;return;
    end
end
roots=topmost(blocks);
end

function tf=blocks_owned_by_roots(blocks,roots)
blocks=string(blocks(:));roots=string(roots(:));tf=false(size(blocks));
for i=1:numel(blocks)
    tf(i)=any(blocks(i)==roots|startsWith(blocks(i),roots+"/") ...
        |startsWith(roots,blocks(i)+"/"));
end
end

function [sensor,reason]=vdc_measurement(G,base)
sensor="";reason="VDC_PHYSICAL_MEASUREMENT_UNRESOLVED";
items=field_items(base,'output_reports');hits=strings(0,1);
for i=1:numel(items)
    r=items{i};if ~isstruct(r)||~isfield(r,'name')||string(r.name)~="Vdc" ...
            ||~logical_field(r,'ok')||~logical_field(r,'provenance_ok') ...
            ||~isfield(r,'trace')||~isstruct(r.trace),continue;end
    for q=1:numel(r.trace)
        t=r.trace(q);if ~isfield(t,'path'),continue;end
        b=string(t.path);s=sat_provenance_semantic(char(b));
        if s.trusted&&s.kind=="measurement" ...
                &&contains(s.semantic,"voltage measurement") ...
                &&numel(physical_nodes(G,b))==2,hits(end+1,1)=b;end %#ok<AGROW>
    end
end
hits=topmost(unique(hits,'stable'));
if numel(hits)==1,sensor=hits;reason="OK";
elseif numel(hits)>1,reason="VDC_PHYSICAL_MEASUREMENT_AMBIGUOUS";end
end

function tf=same_native_net(G,start,target)
n=numel(G.nodes);seen=false(1,n);q=double(start(:)');seen(q)=true;tf=false;
while ~isempty(q)
    u=q(1);q(1)=[];if u==target,tf=true;return;end
    neighbours=G.physical_undirected{u};kinds=string(G.physical_edge_kinds{u});
    for k=1:numel(neighbours)
        if kinds(k)~="physical_net"&&kinds(k)~="subsystem_boundary",continue;end
        v=neighbours(k);if ~seen(v),seen(v)=true;q(end+1)=v;end %#ok<AGROW>
    end
end
end

function ids=physical_nodes(G,blocks)
ids=[];for b=string(blocks(:))'
    ids=[ids find(string({G.nodes.block})==b ...
        &string({G.nodes.network})=="physical")]; %#ok<AGROW>
end;ids=unique(ids);
end
function ids=signal_nodes(G,blocks,kind)
ids=[];for b=string(blocks(:))'
    hit=find(string({G.nodes.block})==b&string({G.nodes.network})=="signal");
    fields=lower(string({G.nodes(hit).port_field}));
    if kind=="in",hit=hit(contains(fields,"in")|fields=="enable"|fields=="trigger");
    else,hit=hit(contains(fields,"out")|fields=="state");end
    ids=[ids hit]; %#ok<AGROW>
end;ids=unique(ids);
end
function seen=graph_reach(adj,start,n)
seen=false(1,n);q=unique(double(start(:)'));q=q(q>=1&q<=n);seen(q)=true;
while ~isempty(q),u=q(1);q(1)=[];
    for v=adj{u},if ~seen(v),seen(v)=true;q(end+1)=v;end,end %#ok<AGROW>
end
end
function out=topmost(blocks)
blocks=unique(string(blocks(:)),'stable');out=strings(0,1);
for i=1:numel(blocks)
    other=blocks((1:numel(blocks))~=i);
    if ~any(startsWith(blocks(i),other+"/")),out(end+1,1)=blocks(i);end %#ok<AGROW>
end
end
function G=task_graph(model,state)
if isstruct(state)&&isfield(state,'model_graph')&&isstruct(state.model_graph) ...
        &&isfield(state.model_graph,'schema') ...
        &&string(state.model_graph.schema)=="simuverity.sat-model-graph.v1"
    G=state.model_graph;else,G=sat_model_graph(char(string(model)));end
end
function items=field_items(s,name)
if ~isstruct(s)||~isscalar(s)||~isfield(s,name)||isempty(s.(name)),items={};
elseif iscell(s.(name)),items=s.(name)(:).';
else,items=arrayfun(@(x)x,s.(name),'UniformOutput',false);end
end
function tf=logical_field(s,name)
tf=isstruct(s)&&isfield(s,name)&&isscalar(s.(name))&&logical(s.(name));
end
function tf=has_fixture(state)
tf=isstruct(state)&&isscalar(state)&&isfield(state,'evidence') ...
    &&isstruct(state.evidence)&&isfield(state.evidence,'unit_test_energy_path_facts');
end
function v=getp(block,param),v='';try,v=get_param(char(block),param);catch,end,end
function f=empty_facts()
f=struct('source_blocks',strings(0,1),'source_anchor_kind',"", ...
    'ballast_converter_roots',strings(0,1), ...
    'controlled_power_blocks',strings(0,1),'control_interfaces',struct([]), ...
    'vdc_measurement_block',"",'vdc_terminal_count',0, ...
    'dc_rails_distinct',false,'rail_paths_owned',false(1,2), ...
    'rail_physical_paths',{{{}, {}}},'rail_conversion_blocks',{{{}, {}}}, ...
    'same_ballast_stage',false,'physical_energy_path_count',0, ...
    'ac_dc_signal_only',false,'algorithm_constraint',"none");
end
function r=make_report(evaluated,valid,ok,detail,evidence)
r=struct('task',"D022",'id',"D022.energy_path_ownership", ...
    'kind',"task_specific",'semantic_kind',"structure",'scenario',"nominal", ...
    'layer',"qualification",'evaluated',logical(evaluated), ...
    'mandatory',true,'ok',logical(ok),'valid',logical(valid), ...
    'score',double(ok),'detail',string(detail),'evidence',evidence);
end
