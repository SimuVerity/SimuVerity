function [ok,reports] = sat_input_contract(modelName,spec,mode)
%SAT_INPUT_CONTRACT Verify that required workspace inputs bind model parameters.
% Golden models are allowed to use evaluator-side set_param interventions because
% many downloaded reference models predate the benchmark input contract.

if nargin<3||isempty(mode), mode='agent'; end
reports=struct('name',{},'required',{},'binding_count',{},'ok',{},'message',{},'bindings',{});
if ~isfield(spec,'input_contract')||isempty(spec.input_contract)
    ok=true; return;
end
names=fieldnames(spec.input_contract); ok=true;
if strcmpi(mode,'golden')
    for i=1:numel(names)
        reports(end+1)=row(names{i},true,NaN,true,'GOLDEN_EVALUATOR_INTERVENTION',strings(0,1)); %#ok<AGROW>
    end
    return;
end

blocks=find_system(modelName,'LookUnderMasks','on','FollowLinks','on','Type','Block');
for i=1:numel(names)
    name=names{i}; cfg=spec.input_contract.(name);
    required=getbool(cfg,'required',true);
    alternatives=contract_alternatives(cfg); bindingOk=false;
    hits=strings(0,1); diagnostics=strings(0,1); matchedAlternative=NaN;
    for a=1:numel(alternatives)
        alt=alternatives{a};
        [altHits,hitBlocks]=scan_bindings(blocks,name,alt);
        minBindings=getnum(alt,'min_bindings',getnum(cfg,'min_bindings',1));
        minDistinct=getnum(alt,'min_distinct_blocks',getnum(cfg,'min_distinct_blocks',1));
        altOk=numel(altHits)>=minBindings&&numel(unique(hitBlocks))>=minDistinct;
        diagnostics(end+1,1)=sprintf('alt%d bindings=%d/%d blocks=%d/%d', ...
            a,numel(altHits),minBindings,numel(unique(hitBlocks)),minDistinct); %#ok<AGROW>
        if altOk
            bindingOk=true;hits=altHits;matchedAlternative=a;break;
        end
        if numel(altHits)>numel(hits),hits=altHits;end
    end
    bindingOk=~required||bindingOk;
    if bindingOk
        if isnan(matchedAlternative),message='OK'; ...
        else,message=sprintf('OK:ALTERNATIVE_%d',matchedAlternative);end
    else
        message=sprintf('INPUT_UNBOUND:%s %s',name,strjoin(diagnostics,'; '));
    end
    reports(end+1)=row(name,required,numel(hits),bindingOk,message,hits); %#ok<AGROW>
    ok=ok&&bindingOk;
end

function alternatives=contract_alternatives(cfg)
if ~isstruct(cfg)||~isfield(cfg,'binding_alternatives')||isempty(cfg.binding_alternatives)
    alternatives={cfg};return;
end
x=cfg.binding_alternatives;
if iscell(x),items=x(:).';else,items=arrayfun(@(z)z,x,'UniformOutput',false);end
alternatives=cell(size(items));
for i=1:numel(items)
    % An alternative inherits connection/physical-role defaults from the
    % parent contract, then overrides only the fields it declares.
    base=cfg;if isfield(base,'binding_alternatives'),base=rmfield(base,'binding_alternatives');end
    alt=items{i};fields=fieldnames(alt);
    for k=1:numel(fields),base.(fields{k})=alt.(fields{k});end
    alternatives{i}=base;
end
end

function [hits,hitBlocks]=scan_bindings(blocks,name,cfg)
blockPatterns=getcell(cfg,'required_block_any',{});
referencePatterns=getcell(cfg,'required_reference_any',{});
paramPatterns=getcell(cfg,'required_parameter_any',{});
hits=strings(0,1);hitBlocks=strings(0,1);
for j=1:numel(blocks)
    b=blocks{j};
    try
        commented=string(get_param(b,'Commented'));
        if strcmpi(commented,'on'), continue; end
    catch
    end
    if getbool(cfg,'require_connected',true)&&~block_connected(b),continue;end
    if getbool(cfg,'require_conserving_connection',false)&&~conserving_connected(b),continue;end
    context=lower(string(b));
    try,context=context+" "+lower(string(get_param(b,'BlockType')));catch,end
    try,context=context+" "+lower(string(get_param(b,'MaskType')));catch,end
    if ~matches_any(context,blockPatterns),continue;end
    reference=trusted_reference_context(b);
    if ~matches_any(reference,referencePatterns),continue;end
    try,dp=get_param(b,'DialogParameters');catch,dp=struct();end
    if ~isstruct(dp),continue;end
    params=fieldnames(dp);
    for k=1:numel(params)
        p=params{k};if ~matches_any(lower(string(p)),paramPatterns),continue;end
        try,value=get_param(b,p);catch,continue;end
        if ~(ischar(value)||isstring(value)),continue;end
        if contains_identifier(string(value),name)
            hits(end+1,1)=string(b)+"::"+string(p)+"="+string(value); %#ok<AGROW>
            hitBlocks(end+1,1)=string(b); %#ok<AGROW>
        end
    end
end
[hits,ix]=unique(hits,'stable');hitBlocks=hitBlocks(ix);
end

function tf=block_connected(block)
tf=false;
try
    ph=get_param(block,'PortHandles'); fields=fieldnames(ph);
    for i=1:numel(fields)
        hs=ph.(fields{i});
        for j=1:numel(hs)
            try, lh=get_param(hs(j),'Line'); catch, lh=-1; end
            if isnumeric(lh)&&any(lh~=-1), tf=true; return; end
        end
    end
catch
end
end

function tf=conserving_connected(block)
% Require a real Simscape/Specialized-Power-Systems conserving connection,
% not merely a signal line on a Constant/Gain whose name looks physical.
tf=false;
try
    ph=get_param(block,'PortHandles');
    fields=intersect(fieldnames(ph),{'LConn','RConn','Conn'},'stable');
    for i=1:numel(fields)
        hs=ph.(fields{i});
        for j=1:numel(hs)
            try,lh=get_param(hs(j),'Line');catch,lh=-1;end
            if isnumeric(lh)&&any(lh~=-1),tf=true;return;end
        end
    end
catch
end
end

function value=trusted_reference_context(block)
% ReferenceBlock is library-owned and survives arbitrary user renaming;
% unlike the block path or a user-created MaskType it cannot be supplied by
% an ordinary unlinked subsystem. Whitespace/newlines are normalized so
% native Simscape library labels remain representation-independent.
value="";
try,value=string(get_param(block,'ReferenceBlock'));catch,end
value=lower(regexprep(strtrim(value),'\s+',' '));
value=replace(value,'\','/');
end
end

function tf=contains_identifier(value,name)
pat=['(?<![A-Za-z0-9_])' regexptranslate('escape',char(name)) '(?![A-Za-z0-9_])'];
tf=~isempty(regexp(char(value),pat,'once'));
end
function tf=matches_any(value,patterns)
if isempty(patterns), tf=true; return; end
tf=false;
for i=1:numel(patterns)
    if ~isempty(regexpi(char(value),char(string(patterns{i})),'once')), tf=true; return; end
end
end
function c=getcell(s,f,d)
c=d; if ~isstruct(s)||~isfield(s,f)||isempty(s.(f)), return; end
v=s.(f); if iscell(v), c=v; else, c=cellstr(string(v)); end
end
function v=getnum(s,f,d)
v=d; if isstruct(s)&&isfield(s,f)&&isnumeric(s.(f))&&isscalar(s.(f))&&isfinite(s.(f)), v=double(s.(f)); end
end
function v=getbool(s,f,d)
v=d; if isstruct(s)&&isfield(s,f)&&~isempty(s.(f)), v=logical(s.(f)); end
end
function r=row(name,required,count,passed,message,bindings)
r=struct('name',string(name),'required',logical(required),'binding_count',count, ...
    'ok',logical(passed),'message',string(message),'bindings',bindings);
end
