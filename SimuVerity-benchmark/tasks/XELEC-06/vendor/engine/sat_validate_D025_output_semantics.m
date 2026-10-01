function [reports,sig,evidence]=sat_validate_D025_output_semantics( ...
    modelName,spec,reports,sig)
%SAT_VALIDATE_D025_OUTPUT_SEMANTICS Narrow D025 MATLAB-Function adapter.
% D025 permits a controller to return the measured Vabc/Iabc and a derived
% Pgrid alongside its gate vector.  A generic upstream traversal through a
% MATLAB Function necessarily sees every controller input (including P_ref)
% and therefore cannot prove which input owns a particular output port.
%
% This task-owned adapter is deliberately fail closed.  It is not a global
% S-Function whitelist.  It accepts only a MATLAB Function subsystem whose
% output ports 2/3/4 feed the unique Vabc/Iabc/Pgrid sinks, whose first six
% input ports come from six distinct, natively trusted current/voltage
% sensors, whose chart forwards those inputs verbatim to Vabc/Iabc, and whose
% runtime Pgrid agrees with sum(Vabc.*Iabc)/1000.

evidence=empty_evidence();
if ~isstruct(spec)||~isfield(spec,'id')||string(spec.id)~="D025",return;end
evidence.evaluated=true;
names=["Vabc","Iabc","Pgrid"];
idx=zeros(1,3);
for i=1:3
    idx(i)=find_report(reports,names(i));
    if idx(i)==0||~reports(idx(i)).ok||~isfield(sig,matlab.lang.makeValidName(names(i)))
        evidence.detail="D025_OUTPUT_SET_INCOMPLETE";return;
    end
end

[routeOk,controller,ports,routeDetail]=output_routes(modelName,names);
evidence.controller=controller;evidence.output_ports=ports;
if ~routeOk,evidence.detail=routeDetail;return;end
if ~is_matlab_function(controller)
    evidence.detail="D025_OUTPUT_OWNER_NOT_MATLAB_FUNCTION";return;
end

[sensorOk,currentOrigins,voltageOrigins,sensorDetail]=sensor_inputs(modelName,controller);
evidence.current_sensor_origins=currentOrigins;
evidence.voltage_sensor_origins=voltageOrigins;
if ~sensorOk,evidence.detail=sensorDetail;return;end

[scriptOk,scriptDetail]=verbatim_chart_outputs(controller);
if ~scriptOk,evidence.detail=scriptDetail;return;end

[powerOk,powerEvidence]=power_crosscheck(sig);
evidence.power_crosscheck=powerEvidence;
if ~powerOk,evidence.detail="D025_PGRID_PHYSICAL_CROSSCHECK_FAILED";return;end
[vIndependent,vRho]=independent_channels(sig.Vabc.Y);
[iIndependent,iRho]=independent_channels(sig.Iabc.Y);
evidence.channel_independence=struct('voltage_max_abs_corr',vRho, ...
    'current_max_abs_corr',iRho,'limit',0.95);
if ~vIndependent||~iIndependent
    evidence.detail="D025_MEASURED_PHASE_CHANNELS_NOT_INDEPENDENT";return;
end

evidence.valid=true;evidence.ok=true;evidence.detail="OK";
semantic="d025 port-sensitive physical measurement forwarding";
for i=1:3
    q=idx(i);reports(q).provenance_ok=true;
    reports(q).message="OK:D025_PORT_SENSITIVE_CONTROLLER nrmse="+ ...
        string(sprintf('%.6g',powerEvidence.normalized_rmse));
    reports(q).trace(end+1)=struct('path',string(controller), ...
        'name',"D025 verified output port "+string(ports(i)), ...
        'block_type',"SubSystem",'mask_type',"MATLAB Function", ...
        'reference_block',"",'trusted_semantic',semantic, ...
        'depth',0,'descriptor',semantic+"|"+names(i)); %#ok<AGROW>
    if names(i)=="Vabc"
        reports(q).channel_origins=voltageOrigins';
    elseif names(i)=="Iabc"
        reports(q).channel_origins=currentOrigins';
    end
    key=matlab.lang.makeValidName(names(i));sig.(key).provenance_ok=true;
end
end

function [ok,controller,ports,detail]=output_routes(model,names)
ok=false;controller="";ports=zeros(1,numel(names));detail="D025_OUTPUT_ROUTE_UNRESOLVED";
try
    blocks=find_system(model,'LookUnderMasks','on','FollowLinks','on','BlockType','ToWorkspace');
catch
    detail="D025_MODEL_NOT_AVAILABLE_FOR_OUTPUT_PROOF";return;
end
for i=1:numel(names)
    hits={};
    for q=1:numel(blocks)
        if string(getp(blocks{q},'VariableName'))==names(i),hits{end+1}=blocks{q};end %#ok<AGROW>
    end
    if numel(hits)~=1,detail="D025_OUTPUT_SINK_NOT_UNIQUE:"+names(i);return;end
    [srcBlock,srcPort]=direct_source(hits{1});
    if strlength(srcBlock)==0,detail="D025_OUTPUT_NOT_DIRECTLY_DRIVEN:"+names(i);return;end
    if i==1,controller=srcBlock;elseif controller~=srcBlock
        detail="D025_OUTPUTS_HAVE_DIFFERENT_OWNERS";return;
    end
    ports(i)=srcPort;
end
if ~isequal(ports,[2 3 4]),detail="D025_OUTPUT_PORT_CONTRACT_MISMATCH";return;end
ok=true;detail="OK";
end

function [block,port]=direct_source(sink)
block="";port=NaN;
try
    ph=get_param(sink,'PortHandles');
    if numel(ph.Inport)~=1,return;end
    line=get_param(ph.Inport(1),'Line');if isempty(line)||line<0,return;end
    src=get_param(line,'SrcPortHandle');if numel(src)~=1||src<0,return;end
    block=string(get_param(src,'Parent'));port=double(get_param(src,'PortNumber'));
catch
    block="";port=NaN;
end
end

function ok=is_matlab_function(block)
ok=false;
try
    ok=strcmpi(strtrim(get_param(block,'BlockType')),'SubSystem') ...
        &&strcmpi(strtrim(get_param(block,'SFBlockType')),'MATLAB Function') ...
        &&isempty(strtrim(getp(block,'ReferenceBlock')));
catch
end
end

function [ok,currentOrigins,voltageOrigins,detail]=sensor_inputs(model,controller)
ok=false;currentOrigins=strings(0,1);voltageOrigins=strings(0,1);
detail="D025_CONTROLLER_SENSOR_INPUTS_INVALID";
for p=1:6
    trace=sat_trace_upstream(model,controller,p,16);
    if isempty(trace),detail="D025_CONTROLLER_INPUT_TRACE_EMPTY:"+string(p);return;end
    semantics=lower(string({trace.trusted_semantic}));
    if p<=3
        mask=contains(semantics,"current measurement");
    else
        mask=contains(semantics,"voltage measurement");
    end
    origins=unique(string({trace(mask).path}),'stable');
    if numel(origins)~=1
        detail="D025_CONTROLLER_SENSOR_ORIGIN_NOT_UNIQUE:"+string(p);return;
    end
    if p<=3
        currentOrigins(end+1,1)=origins; %#ok<AGROW>
    else
        voltageOrigins(end+1,1)=origins; %#ok<AGROW>
    end
end
if numel(unique(currentOrigins))~=3||numel(unique(voltageOrigins))~=3 ...
        ||~isempty(intersect(currentOrigins,voltageOrigins))
    detail="D025_CONTROLLER_SENSOR_ORIGINS_NOT_DISTINCT";return;
end
ok=true;detail="OK";
end

function [ok,detail]=verbatim_chart_outputs(controller)
ok=false;detail="D025_MATLAB_FUNCTION_SCRIPT_UNREADABLE";script="";
try
    root=sfroot;charts=root.find('-isa','Stateflow.EMChart');
    for i=1:numel(charts)
        if string(charts(i).Path)==string(controller),script=string(charts(i).Script);break;end
    end
catch
end
if strlength(script)==0,return;end
% Only the two raw measurement outputs are recognized statically.  Pgrid is
% authenticated numerically below, so equivalent abc/dq power formulas are
% not constrained to one implementation spelling.
vpat='(?m)\<Vabc\>\s*=\s*\[\s*va\s*[,;]\s*vb\s*[,;]\s*vc\s*\]\s*;';
ipat='(?m)\<Iabc\>\s*=\s*\[\s*ia\s*[,;]\s*ib\s*[,;]\s*ic\s*\]\s*;';
if numel(regexpi(char(script),'(?m)\<Vabc\>\s*=','match'))~=1 ...
        ||isempty(regexpi(char(script),vpat,'once'))
    detail="D025_VABC_NOT_VERBATIM_SENSOR_FORWARD";return;
end
if numel(regexpi(char(script),'(?m)\<Iabc\>\s*=','match'))~=1 ...
        ||isempty(regexpi(char(script),ipat,'once'))
    detail="D025_IABC_NOT_VERBATIM_SENSOR_FORWARD";return;
end
% A syntactically valid forwarding line followed by a second overwrite must
% not pass.  Likewise, the six sensor input variables themselves must remain
% immutable within the chart.  Reject evaluator/workspace access and random
% or wall-clock dependencies in this narrow provenance adapter.
for name=["ia","ib","ic","va","vb","vc"]
    pat=['(?m)\<' char(name) '\>\s*(\([^;=]*\))?\s*='];
    if ~isempty(regexpi(char(script),pat,'once'))
        detail="D025_SENSOR_INPUT_REASSIGNED:"+name;return;
    end
end
forbidden='(?i)\<(evalin|assignin|global|rand|randn|randi|time|clock|now|datetime|tic|toc|get_param|set_param)\>';
if ~isempty(regexp(char(script),forbidden,'once'))
    detail="D025_CONTROLLER_EXTERNAL_OR_RANDOM_DEPENDENCY";return;
end
ok=true;detail="OK";
end

function [ok,e]=power_crosscheck(sig)
e=struct('valid',false,'samples',0,'normalized_rmse',Inf, ...
    'p99_relative_error',Inf,'limit_nrmse',0.01,'limit_p99',0.03);
ok=false;
try
    V=double(sig.Vabc.Y);I=double(sig.Iabc.Y);P=double(sig.Pgrid.Y(:,1));
    tv=double(sig.Vabc.t(:));ti=double(sig.Iabc.t(:));tp=double(sig.Pgrid.t(:));
catch
    return;
end
if size(V,2)~=3||size(I,2)~=3||size(V,1)~=size(I,1)||size(V,1)~=numel(P) ...
        ||numel(tv)~=numel(ti)||numel(tv)~=numel(tp)||numel(tv)<128,return;end
timeTol=1e-10*max(1,max(abs(tv)));
if max(abs(tv-ti))>timeTol||max(abs(tv-tp))>timeTol,return;end
expected=sum(V.*I,2)/1000;mask=isfinite(expected)&isfinite(P);
if nnz(mask)<128,return;end
expected=expected(mask);P=P(mask);err=P-expected;
scale=max(1,sqrt(mean(expected.^2)));
nrmse=sqrt(mean(err.^2))/scale;
rel=abs(err)/scale;rel=sort(rel);p99=rel(max(1,ceil(0.99*numel(rel))));
e.valid=true;e.samples=numel(err);e.normalized_rmse=nrmse;e.p99_relative_error=p99;
ok=isfinite(nrmse)&&isfinite(p99)&&nrmse<=e.limit_nrmse&&p99<=e.limit_p99;
end

function [ok,rho]=independent_channels(Y)
ok=false;rho=Inf;
try,Y=double(Y);catch,return;end
if size(Y,2)~=3||size(Y,1)<16||any(~isfinite(Y),'all'),return;end
first=max(1,floor(0.8*size(Y,1))+1);Z=Y(first:end,:);
scale=max(abs(Z),[],'all');
if any(std(Z,0,1)<=max(1e-12,1e-9*scale)),return;end
C=abs(corrcoef(Z));C(1:4:end)=0;rho=max(C,[],'all');
ok=isfinite(rho)&&rho<=0.95;
end

function idx=find_report(reports,name)
hits=find(string({reports.name})==string(name));
if numel(hits)==1,idx=hits;else,idx=0;end
end
function value=getp(block,param)
value='';try,value=get_param(block,param);catch,end
if isnumeric(value),value=num2str(value);end
end
function e=empty_evidence()
e=struct('evaluated',false,'valid',false,'ok',false,'detail',"NOT_APPLICABLE", ...
    'controller',"",'output_ports',zeros(1,0), ...
    'current_sensor_origins',strings(0,1), ...
    'voltage_sensor_origins',strings(0,1),'power_crosscheck',struct());
end
