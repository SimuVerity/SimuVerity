function report=sat_check_D015_active_svpwm_gate_ownership( ...
    modelName,spec,scenarioId,simOut,signals,baseReports,state) %#ok<INUSD>
%SAT_CHECK_D015_ACTIVE_SVPWM_GATE_OWNERSHIP D015 power-path ownership.
% The source function/report id remains stable for public report compatibility.
% The verdict is modulation-neutral: the active path must contain an
% ordered rectifier and controllable inverter, physical DC storage, and
% provenance-qualified independent three-phase terminal measurements.

if string(scenarioId)~="nominal",report=struct([]);return;end
if ~isstruct(spec)||~isscalar(spec)||~isfield(spec,'id')||string(spec.id)~="D015"
    report=make_report(false,false,false,"TASK_IDENTITY_MISMATCH",struct());return;
end
if has_fixture(state)
    facts=state.evidence.unit_test_facts;valid=true;reason="OK";
else
    try,[facts,valid,reason]=extract_facts(modelName,baseReports);
    catch ex
        report=make_report(false,false,false,"EXTRACTION_ERROR:"+string(ex.identifier),struct());return;
    end
end
if ~valid,report=make_report(false,false,false,reason,facts);return;end
[schemaOk,ok,detail]=verdict(facts);
report=make_report(true,schemaOk,ok,detail,facts);
end

function [facts,valid,reason]=extract_facts(modelName,base)
facts=empty_facts();valid=false;reason="";
[pathReport,ok,why]=unique_report(base,'struct_reports',"source_rectifier_inverter_to_measured_output");
if ~ok,reason=why;return;end
if ~logical_field(pathReport,'ok')||~isfield(pathReport,'evidence') ...
        ||~isstruct(pathReport.evidence)||~isfield(pathReport.evidence,'path')
    reason="SOURCE_RECTIFIER_INVERTER_LOAD_PATH_FAILED";return;
end
path=string(pathReport.evidence.path(:));path=path(strlength(path)>0);
if isempty(path),reason="SOURCE_RECTIFIER_INVERTER_LOAD_PATH_EMPTY";return;end

rectifier=false(size(path));controllable=false(size(path));
for i=1:numel(path)
    rectifier(i)=is_rectifier_stage(path(i));
    controllable(i)=is_controllable_stage(path(i));
end
ordered=false;
for r=find(rectifier(:))'
    if any(find(controllable(:))>r),ordered=true;break;end
end

[dcReport,ok,why]=unique_report(base,'struct_reports',"dc_link_storage");
if ~ok,reason=why;return;end
[vdc,ok,why]=output_facts(base,"Vdc",1);if ~ok,reason=why;return;end
[vabc,ok,why]=output_facts(base,"Vabc",3);if ~ok,reason=why;return;end
[iabc,ok,why]=output_facts(base,"Iabc",3);if ~ok,reason=why;return;end

facts.energy_path_blocks=path;
facts.rectifier_blocks=path(rectifier);
facts.controllable_inverter_blocks=path(controllable);
facts.rectifier_precedes_inverter=ordered;
facts.dc_link_storage_present=logical_field(dcReport,'ok');
facts.vdc_physical_measurement=vdc.physical;
facts.vabc_physical_measurement=vabc.physical;
facts.iabc_physical_measurement=iabc.physical;
facts.vabc_channels=vabc.channels;facts.iabc_channels=iabc.channels;
facts.vabc_distinct_origins=vabc.distinct;facts.iabc_distinct_origins=iabc.distinct;
facts.iabc_measurement_on_energy_path=any(ismember(path,iabc.trace_blocks));
[facts.vabc_same_output_stage,facts.vabc_output_path]=same_output_stage( ...
    modelName,path(controllable),vabc.trace_blocks,path(rectifier));
facts.path_evidence=pathReport.evidence;
facts.model=string(modelName);
valid=true;reason="OK";
end

function [schemaOk,ok,detail]=verdict(f)
required={'energy_path_blocks','rectifier_blocks','controllable_inverter_blocks', ...
    'rectifier_precedes_inverter','dc_link_storage_present', ...
    'vdc_physical_measurement','vabc_physical_measurement','iabc_physical_measurement', ...
    'vabc_channels','iabc_channels','vabc_distinct_origins','iabc_distinct_origins', ...
    'iabc_measurement_on_energy_path','vabc_same_output_stage'};
schemaOk=isstruct(f)&&isscalar(f)&&all(isfield(f,required));
if ~schemaOk,ok=false;detail="FACT_SCHEMA_INVALID";return;end
pathOk=~isempty(f.energy_path_blocks)&&~isempty(f.rectifier_blocks) ...
    &&~isempty(f.controllable_inverter_blocks)&&logical(f.rectifier_precedes_inverter);
measureOk=logical(f.vdc_physical_measurement)&&logical(f.vabc_physical_measurement) ...
    &&logical(f.iabc_physical_measurement)&&f.vabc_channels==3&&f.iabc_channels==3 ...
    &&logical(f.vabc_distinct_origins)&&logical(f.iabc_distinct_origins) ...
    &&logical(f.iabc_measurement_on_energy_path)&&logical(f.vabc_same_output_stage);
ok=pathOk&&logical(f.dc_link_storage_present)&&measureOk;
if ok,detail="OK";
elseif isempty(f.rectifier_blocks),detail="RECTIFIER_NOT_ON_ACTIVE_SOURCE_TO_LOAD_PATH";
elseif isempty(f.controllable_inverter_blocks),detail="CONTROLLABLE_INVERTER_NOT_ON_ACTIVE_SOURCE_TO_LOAD_PATH";
elseif ~logical(f.rectifier_precedes_inverter),detail="RECTIFIER_DOES_NOT_PRECEDE_CONTROLLABLE_INVERTER";
elseif ~logical(f.dc_link_storage_present),detail="PHYSICAL_DC_LINK_STORAGE_MISSING";
else,detail="PHYSICAL_THREE_PHASE_MEASUREMENT_INVALID";end
end

function tf=is_rectifier_stage(block)
[d,device]=trusted_descriptor(block);
active=contains(d,"igbt")||contains(d,"mosfet")||contains(d,"gto") ...
    ||contains(device,"igbt")||contains(device,"mosfet")||contains(device,"gto");
tf=contains(d,"rectifier")||contains(d,"diode bridge")||contains(d,"thyristor") ...
    ||contains(device,"thyristor")||((contains(d,"|diode|") ...
    ||contains(device,"diode"))&&~active);
end
function tf=is_controllable_stage(block)
[d,device]=trusted_descriptor(block);
tf=contains(d,"three-level bridge")||contains(d,"igbt")||contains(d,"mosfet") ...
    ||contains(d,"gto")||contains(d,"ideal switch")||contains(device,"igbt") ...
    ||contains(device,"mosfet")||contains(device,"gto")||contains(device,"ideal switch");
end
function [d,device]=trusted_descriptor(block)
parts=strings(0,1);
for p={'BlockType','MaskType','ReferenceBlock'}
    try,parts(end+1)=string(get_param(char(block),p{1}));catch,end %#ok<AGROW>
end
d="|"+lower(strjoin(parts,"|"))+"|";device=lower(string(getp(block,'Device')));
end

function [ok,path]=same_output_stage(model,stages,measurements,rectifiers)
ok=false;path=strings(0,1);stages=unique(string(stages(:)),'stable');
measurements=unique(string(measurements(:)),'stable');
if isempty(stages)||isempty(measurements),return;end
G=sat_model_graph(char(string(model)));
q=struct('network',"physical",'direction',"undirected", ...
    'source',{exact_selectors(stages)},'target',{exact_selectors(measurements)});
[hit,e]=sat_graph_query(G,q);
if ~hit||~isstruct(e)||~isfield(e,'block_path'),return;end
path=string(e.block_path(:));middle=path;
if numel(middle)>2,middle=middle(2:end-1);else,middle=strings(0,1);end
ok=isempty(intersect(middle,string(rectifiers(:))));
end
function selectors=exact_selectors(blocks)
selectors=cell(1,numel(blocks));
for i=1:numel(blocks),selectors{i}=struct('block',blocks(i));end
end

function [o,ok,reason]=output_facts(base,name,expectedChannels)
o=struct('physical',false,'channels',0,'distinct',false, ...
    'trace_blocks',strings(0,1));ok=false;
[r,uniqueOk,why]=unique_report(base,'output_reports',name);
if ~uniqueOk,reason=why;return;end
if ~logical_field(r,'ok')||~logical_field(r,'provenance_ok')
    reason=name+"_PHYSICAL_PROVENANCE_FAILED";return;
end
if ~isfield(r,'channels')||~isscalar(r.channels)||~isfinite(r.channels)
    reason=name+"_CHANNEL_COUNT_MISSING";return;
end
o.physical=true;o.channels=double(r.channels);
if isfield(r,'trace')&&isstruct(r.trace)&&~isempty(r.trace)&&isfield(r.trace,'path')
    o.trace_blocks=unique(string({r.trace.path}),'stable');
end
if expectedChannels==1,o.distinct=true;
elseif isfield(r,'channel_origins')
    origins=string(r.channel_origins(:));origins=origins(strlength(origins)>0);
    o.distinct=numel(origins)==expectedChannels&&numel(unique(origins))==expectedChannels;
end
ok=true;reason="OK";
end

function [r,ok,reason]=unique_report(base,collection,id)
r=[];ok=false;reason=upper(id)+"_REPORT_MISSING";items=field_items(base,collection);matches={};
for i=1:numel(items)
    x=items{i};key="";
    if string(collection)=="output_reports"&&isstruct(x)&&isfield(x,'name'),key=string(x.name);
    elseif isstruct(x)&&isfield(x,'id'),key=string(x.id);end
    if key==id,matches{end+1}=x;end %#ok<AGROW>
end
if numel(matches)~=1,if numel(matches)>1,reason=upper(id)+"_REPORT_AMBIGUOUS";end;return;end
r=matches{1};ok=true;reason="OK";
end
function items=field_items(s,name)
if ~isstruct(s)||~isscalar(s)||~isfield(s,name)||isempty(s.(name)),items={};
elseif iscell(s.(name)),items=s.(name)(:).';
else,items=arrayfun(@(x)x,s.(name),'UniformOutput',false);end
end
function value=logical_field(s,name),value=isstruct(s)&&isfield(s,name)&&isscalar(s.(name))&&logical(s.(name));end
function v=getp(block,param),v='';try,v=get_param(char(block),param);catch,end,end
function tf=has_fixture(state),tf=isstruct(state)&&isscalar(state)&&isfield(state,'evidence')&&isstruct(state.evidence)&&isfield(state.evidence,'unit_test_facts');end
function f=empty_facts()
f=struct('energy_path_blocks',strings(0,1),'rectifier_blocks',strings(0,1), ...
    'controllable_inverter_blocks',strings(0,1),'rectifier_precedes_inverter',false, ...
    'dc_link_storage_present',false,'vdc_physical_measurement',false, ...
    'vabc_physical_measurement',false,'iabc_physical_measurement',false, ...
    'vabc_channels',0,'iabc_channels',0,'vabc_distinct_origins',false, ...
    'iabc_distinct_origins',false,'iabc_measurement_on_energy_path',false, ...
    'vabc_same_output_stage',false,'vabc_output_path',strings(0,1), ...
    'path_evidence',struct(),'model',"");
end
function r=make_report(evaluated,valid,ok,detail,evidence)
r=struct('task',"D015",'id',"D015.active_svpwm_gate_ownership", ...
    'kind',"task_specific",'semantic_kind',"structure",'scenario',"nominal", ...
    'layer',"qualification",'evaluated',logical(evaluated),'mandatory',true, ...
    'ok',logical(ok),'valid',logical(valid),'score',double(ok), ...
    'detail',string(detail),'evidence',evidence);
end
