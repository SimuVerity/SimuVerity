function [sig, coreOk, provenanceOk, reports] = sat_output_contract(simOut, modelName, spec)
%SAT_OUTPUT_CONTRACT Read and strictly validate schema contract outputs.

sig=struct(); coreOk=true; provenanceOk=true;
reports=struct('name',{},'role',{},'ok',{},'format',{},'samples',{},'channels',{}, ...
    'coverage',{},'time_start',{},'time_end',{},'provenance_ok',{},'trace',{},'channel_origins',{},'message',{});

stopTime=double(spec.sim.stop);
for i=1:numel_any(spec.outputs)
    o=elem(spec.outputs,i); name=char(string(o.name)); role=getstr(o,'role','core');
    [Y,t,fmt,ok,msg]=read_output_strict(simOut,name,o);
    samples=size(Y,1); channels=size(Y,2); coverage=0;
    if ok
        coverage=max(0,(t(end)-t(1))/max(stopTime,eps));
        minSamples=getnum(o,'min_samples',16); minChannels=getnum(o,'min_channels',1); maxChannels=getnum(o,'max_channels',Inf);
        minCoverage=getnum(o,'time_coverage',0.95);
        if samples<minSamples, ok=false; msg=sprintf('SAMPLES_%d_LT_%d',samples,minSamples); end
        if ok&&channels<minChannels, ok=false; msg=sprintf('CHANNELS_%d_LT_%d',channels,minChannels); end
        if ok&&channels>maxChannels, ok=false; msg=sprintf('CHANNELS_%d_GT_%d',channels,maxChannels); end
        if ok&&coverage+1e-9<minCoverage, ok=false; msg=sprintf('COVERAGE_%.5g_LT_%.5g',coverage,minCoverage); end
        if ok&&any(~isfinite(Y),'all'), ok=false; msg='NONFINITE_DATA'; end
        if ok&&(numel(t)<2||any(~isfinite(t))||any(diff(t)<=0)), ok=false; msg='INVALID_TIME_AXIS'; end
    end

    provOk=true; trace=struct([]); channelOrigins=strings(1,0); provMsg='';
    if ok&&isfield(o,'provenance')&&~isempty(o.provenance)
        [provOk,trace,provMsg]=validate_provenance(modelName,name,o.provenance);
        if provOk&&getbool(o.provenance,'require_independent_channels',false)
            [provOk,guardMsg]=validate_independent_channels(Y,o.provenance);
            if ~provOk,provMsg=guardMsg;end
        end
        needsOrigins=getbool(o.provenance,'require_distinct_channel_origins',false)||isfield(o.provenance,'distinct_group');
        if provOk&&needsOrigins
            [provOk,channelOrigins,guardMsg]=validate_channel_origins(modelName,name,channels,o.provenance);
            if ~provOk,provMsg=guardMsg;end
        end
    end

    if ok
        key=matlab.lang.makeValidName(name);
        sig.(key)=struct('y',Y(:,1),'t',t,'Y',Y,'format',fmt,'coverage',coverage,'provenance_ok',provOk);
    end
    if strcmpi(role,'core')
        if ~ok, coreOk=false; end
        if ~provOk, provenanceOk=false; end
    end
    if ~provOk
        if isempty(msg), msg=['PROVENANCE:' provMsg]; else, msg=[msg ';PROVENANCE:' provMsg]; end
    end
    ts=NaN; te=NaN; if ~isempty(t), ts=t(1); te=t(end); end
    reports(end+1)=struct('name',string(name),'role',string(role),'ok',logical(ok), ...
        'format',string(fmt),'samples',samples,'channels',channels,'coverage',coverage, ...
        'time_start',ts,'time_end',te,'provenance_ok',logical(provOk), ...
        'trace',trace,'channel_origins',channelOrigins,'message',string(msg)); %#ok<AGROW>
end
% A D025 MATLAB Function may return gate commands and measured outputs from
% different output ports. Generic upstream traversal cannot distinguish
% those ports once it enters the opaque Stateflow S-Function. Apply the
% narrow task-owned, port-sensitive adapter; it fails closed and does not
% relax the generic provenance rules or trust arbitrary S-Functions.
if isfield(spec,'id')&&string(spec.id)=="D025"
    [reports,sig]=sat_validate_D025_output_semantics(modelName,spec,reports,sig);
end
[reports,sig]=enforce_distinct_groups(spec,reports,sig);
coreOk=true;provenanceOk=true;
for i=1:numel_any(spec.outputs)
    o=elem(spec.outputs,i);if ~strcmpi(getstr(o,'role','core'),'core'),continue;end
    if ~reports(i).ok,coreOk=false;end
    if ~reports(i).provenance_ok,provenanceOk=false;end
end
end

function [Y,t,fmt,ok,msg]=read_output_strict(so,name,o)
Y=[]; t=[]; fmt=''; ok=false; msg='SIGNAL_MISSING'; value=[]; found=false;
try, value=so.get(name); found=true; catch, end
if ~found
    try
        ds=so.get('logsout'); if ~isempty(ds), el=ds.getElement(name); value=el.Values; found=true; end
    catch
    end
end
if ~found
    try, ds=so.get('yout'); el=ds.getElement(name); value=el.Values; found=true; catch, end
end
if ~found, return; end

[Y,t,fmt,ok,msg]=unpack_strict(value,o);
end

function [Y,t,fmt,ok,msg]=unpack_strict(v,o)
Y=[]; t=[]; fmt=''; ok=false; msg='UNSUPPORTED_OUTPUT_TYPE';
if isa(v,'Simulink.SimulationData.Signal')
    [Y,t,fmt,ok,msg]=unpack_strict(v.Values,o); return;
elseif isa(v,'timeseries')
    t=double(v.Time(:));fmt='timeseries';
    [Y,ok,msg]=chanmat(v.Data,numel(t));
elseif isstruct(v)&&isfield(v,'time')&&isfield(v,'signals')&&~isempty(v.signals)
    expected=getstr(o,'datatype','timeseries');
    if ~strcmpi(expected,'structure_with_time')&&~getbool(o,'allow_structure_with_time',false)
        msg='STRUCTURE_WITH_TIME_NOT_ALLOWED'; return;
    end
    t=double(v.time(:));fmt='structure_with_time';
    [Y,ok,msg]=chanmat(v.signals(1).values,numel(t));
elseif isnumeric(v)&&~isempty(v)
    if ~getbool(o,'allow_numeric',false), msg='NUMERIC_WITHOUT_TIME_REJECTED'; return; end
    msg='NUMERIC_REQUIRES_EXPLICIT_TIME'; return;
end
if ok&&size(Y,1)~=numel(t), ok=false; msg='TIME_DATA_LENGTH_MISMATCH'; end
if ok&&isrow(t), t=t(:); end
end

function [ok,trace,msg]=validate_provenance(modelName,varName,p)
ok=false; trace=struct([]); msg='TO_WORKSPACE_NOT_FOUND';
blks=find_system(modelName,'LookUnderMasks','on','FollowLinks','on','BlockType','ToWorkspace'); matches={};
for i=1:numel(blks)
    v=''; try, v=get_param(blks{i},'VariableName'); catch, end
    if strcmp(strtrim(v),varName), matches{end+1}=blks{i}; end %#ok<AGROW>
end
if numel(matches)~=1
    if isempty(matches), msg='TO_WORKSPACE_NOT_FOUND'; else, msg='MULTIPLE_TO_WORKSPACE_BLOCKS'; end
    return;
end
maxDepth=getnum(p,'max_trace_depth',24); trace=sat_trace_upstream(modelName,matches{1},1,maxDepth);
if isempty(trace), msg='EMPTY_UPSTREAM_TRACE'; return; end
desc=strjoin([trace.descriptor],' || ');
trustedDesc=strjoin(lower([string({trace.block_type}),string({trace.mask_type}),string({trace.reference_block})]),' || ');
semanticDesc=strjoin(lower(string({trace.trusted_semantic})),' || ');

forbidden=getstrings(p,'forbidden_upstream');
for q=1:numel(forbidden)
    if ~isempty(regexpi(desc,forbidden{q},'once')), msg=['FORBIDDEN:' forbidden{q}]; return; end
end
required=getstrings(p,'required_upstream');
for q=1:numel(required)
    haystack=required_haystack(required{q},desc,trustedDesc,semanticDesc);
    if isempty(regexpi(haystack,required{q},'once')), msg=['REQUIRED_MISSING:' required{q}]; return; end
end
requiredAny=getstrings(p,'required_any_upstream');
if ~isempty(requiredAny)
    hit=false; for q=1:numel(requiredAny), haystack=required_haystack(requiredAny{q},desc,trustedDesc,semanticDesc);if ~isempty(regexpi(haystack,requiredAny{q},'once')), hit=true; break; end, end
    if ~hit, msg=['REQUIRED_ANY_MISSING:' strjoin(requiredAny,'|')]; return; end
end
ok=true; msg='OK';
end

function haystack=required_haystack(pattern,fullDesc,trustedDesc,semanticDesc)
key=lower(regexprep(string(pattern),'\\',''));
measurementTokens=["voltage measurement","voltage sensor","current measurement", ...
    "current sensor","three-phase vi measurement","multimeter","power (3ph", ...
    "power measurement","machine measurement","ps-simulink converter"];
trustedMetadata='synchronous\s*generator|permanent\s*magnet\s*synchronous\s*machine|^machine$';
if any(contains(key,measurementTokens))
    haystack=semanticDesc;
elseif ~isempty(regexpi(pattern,trustedMetadata,'once'))
    haystack=trustedDesc;
else
    haystack=fullDesc;
end
end

function [ok,msg]=validate_independent_channels(Y,p)
ok=false;msg='CHANNELS_NOT_INDEPENDENT';
if size(Y,2)<2,msg='CHANNEL_INDEPENDENCE_REQUIRES_MULTICHANNEL';return;end
frac=getnum(p,'independence_steady_fraction',0.2);n=size(Y,1);first=max(1,floor((1-frac)*n)+1);Z=double(Y(first:end,:));
if size(Z,1)<8||any(~isfinite(Z),'all'),msg='CHANNEL_INDEPENDENCE_INVALID_DATA';return;end
if any(std(Z,0,1)<=max(1e-12,1e-9*max(abs(Z),[],'all'))),msg='CHANNEL_INDEPENDENCE_DEGENERATE';return;end
C=abs(corrcoef(Z));C(1:size(C,1)+1:end)=0;rho=max(C,[],'all');limit=getnum(p,'max_abs_channel_corr',0.95);
ok=isfinite(rho)&&rho<=limit;if ok,msg=sprintf('OK max_abs_corr=%.6g',rho);else,msg=sprintf('CHANNELS_NOT_INDEPENDENT max_abs_corr=%.6g limit=%.6g',rho,limit);end
end

function [ok,origins,msg]=validate_channel_origins(modelName,varName,channels,p)
ok=false;origins=strings(1,0);msg='CHANNEL_ORIGINS_UNRESOLVED';sink=workspace_sink(modelName,varName);if isempty(sink),msg='TO_WORKSPACE_NOT_FOUND';return;end
[origins,traced,detail]=sat_channel_origins(modelName,sink,1,channels,getnum(p,'max_trace_depth',32));
if ~traced,msg='CHANNEL_ORIGINS_UNRESOLVED:'+string(detail);return;end
ok=numel(unique(origins))==channels;if ok,msg='OK';else,msg='CHANNEL_ORIGINS_NOT_DISTINCT:'+strjoin(origins,',');end
end

function [reports,sig]=enforce_distinct_groups(spec,reports,sig)
groups=strings(1,numel_any(spec.outputs));
for i=1:numel_any(spec.outputs)
    o=elem(spec.outputs,i);if isfield(o,'provenance')&&isfield(o.provenance,'distinct_group'),groups(i)=string(o.provenance.distinct_group);end
end
names=unique(groups(strlength(groups)>0));
for g=1:numel(names)
    ix=find(groups==names(g));if numel(ix)<2,continue;end
    signatures=strings(1,numel(ix));for k=1:numel(ix),signatures(k)=strjoin(string(reports(ix(k)).channel_origins),'|');end
    if any(strlength(signatures)==0)||numel(unique(signatures))<numel(signatures)
        for k=1:numel(ix)
            q=ix(k);reports(q).provenance_ok=false;extra="DISTINCT_GROUP_DUPLICATE:"+names(g)+":"+strjoin(signatures,',');
            if strlength(reports(q).message)==0,reports(q).message="PROVENANCE:"+extra;else,reports(q).message=reports(q).message+";PROVENANCE:"+extra;end
            key=matlab.lang.makeValidName(char(string(reports(q).name)));if isfield(sig,key),sig.(key).provenance_ok=false;end
        end
    end
end
end


function sink=workspace_sink(modelName,varName)
sink='';blks=find_system(modelName,'LookUnderMasks','on','FollowLinks','on','BlockType','ToWorkspace');matches={};
for i=1:numel(blks),try,if strcmp(strtrim(get_param(blks{i},'VariableName')),varName),matches{end+1}=blks{i};end,catch,end,end %#ok<AGROW>
if numel(matches)==1,sink=matches{1};end
end


function [d,ok,msg]=chanmat(d,timeCount)
ok=false;msg='TIME_DIMENSION_NOT_FOUND';
try,d=double(d);catch,msg='OUTPUT_DATA_NOT_NUMERIC';return;end
if isempty(d)||~isscalar(timeCount)||timeCount<1,return;end
dims=size(d);hits=find(dims==timeCount);
if isempty(hits),return;end
if numel(hits)~=1,msg='TIME_DIMENSION_AMBIGUOUS';return;end
timeDim=hits(1);order=[timeDim setdiff(1:numel(dims),timeDim,'stable')];
d=permute(d,order);d=reshape(d,timeCount,[]);
if isempty(d)||size(d,1)~=timeCount,msg='TIME_DATA_LENGTH_MISMATCH';return;end
ok=true;msg='';
end
function n=numel_any(a), n=numel(a); end
function e=elem(a,i), if iscell(a), e=a{i}; else, e=a(i); end, end
function v=getnum(s,f,d), v=d; if isfield(s,f)&&~isempty(s.(f))&&isnumeric(s.(f))&&isscalar(s.(f))&&isfinite(s.(f)), v=double(s.(f)); end, end
function v=getstr(s,f,d), v=d; if isfield(s,f)&&~isempty(s.(f)), v=char(string(s.(f))); end, end
function v=getbool(s,f,d), v=d; if isfield(s,f)&&~isempty(s.(f)), v=logical(s.(f)); end, end
function out=getstrings(s,f)
out={}; if ~isfield(s,f)||isempty(s.(f)), return; end
x=s.(f); if iscell(x), out=cellfun(@(z) char(string(z)),x,'UniformOutput',false); else, out=cellstr(string(x)); end
end
