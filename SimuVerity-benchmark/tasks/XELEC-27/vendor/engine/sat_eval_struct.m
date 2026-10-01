function [mandatoryOk, score, detail, reports] = sat_eval_struct(modelName, structural)
%SAT_EVAL_STRUCT Continuous topology score plus mandatory signature gate.

P=sat_prims(); mandatoryOk=true; score=1; detail='(none)';
reports=struct('id',{},'prim',{},'ok',{},'mandatory',{},'weight',{},'detail',{},'evidence',{});
if isempty(structural)||~isfield(structural,'recognizers')||isempty(structural.recognizers), return; end
recs=structural.recognizers; vals=[]; weights=[]; mandatory=[];
for i=1:numel_any(recs)
    rc=elem(recs,i); prim=char(string(rc.prim)); id=getstr(rc,'id',sprintf('r%d',i));
    args=getstrings(rc,'args'); w=getnum(rc,'weight',1); must=getbool(rc,'mandatory',getbool(rc,'signature',false));
    ok=false; msg=''; evidence=struct();
    try
        switch lower(prim)
            case 'has_mask', ok=P.has_mask(modelName,args);
            case 'count_mask', ok=P.count_mask(modelName,args)>=getnum(rc,'k',1);
            case 'has_blocktype', ok=P.has_blocktype(modelName,args);
            case 'count_blocktype', ok=P.count_blocktype(modelName,args{1})>=getnum(rc,'k',1);
            case 'count_capacitor'
                [nCap,capPaths]=count_capacitors(modelName); ok=nCap>=getnum(rc,'k',1);
                msg=sprintf('configured_capacitors=%d required=%g',nCap,getnum(rc,'k',1)); evidence=struct('count',nCap,'paths',capPaths);
            case 'd027_npc_switch_population'
                evidence=sat_d027_npc_population_core(modelName);
                required=getnum(rc,'k',12);
                ok=evidence.equivalent_switch_count>=required;
                msg=sprintf(['D027 equivalent_controllable_switches=%d required=%g ' ...
                    'discrete=%d active_trusted_aggregate=%d'], ...
                    evidence.equivalent_switch_count,required, ...
                    evidence.discrete_switch_count,evidence.active_aggregate_count);
            case 'd027_npc_clamping_diodes'
                evidence=sat_d027_npc_population_core(modelName);
                required=getnum(rc,'k',6);
                ok=evidence.equivalent_clamping_diode_count>=required;
                msg=sprintf(['D027 equivalent_clamping_diodes=%d required=%g ' ...
                    'discrete=%d active_trusted_aggregate=%d'], ...
                    evidence.equivalent_clamping_diode_count,required, ...
                    evidence.discrete_clamping_diode_count,evidence.active_aggregate_count);
            case 'has_name_or_mask', ok=P.has_name_or_mask(modelName,args);
            case 'has_integral_action', ok=P.has_integral_action(modelName);
            case 'three_phase_source', ok=P.three_phase_source(modelName);
            case 'three_phase_bridge', ok=P.three_phase_bridge(modelName);
            case 'has_power_device', ok=P.has_power_device(modelName,args);
            case 'svpwm_verified', ok=svpwm_verified(modelName); msg='strict SVPWM heuristic';
            case 'signal_path'
                [ok,msg]=sat_signal_path(modelName,getstrings(rc,'source'),getstrings(rc,'via'),getstrings(rc,'target'));
            case 'physical_path'
                [ok,msg,evidence]=sat_physical_path(modelName,getstrings(rc,'source'),getstrings(rc,'via'),getstrings(rc,'target'));
                if ok&&getbool(rc,'require_via_cut',false)&&(~isfield(evidence,'via_is_cut')||~logical(evidence.via_is_cut))
                    branchProof=false;
                    if getbool(rc,'allow_d025_foundation_npc_branch_proof',false)
                        G=sat_model_graph(modelName);
                        native=sat_check_D025_foundation_npc(modelName,G,strings(0,1));
                        branchProof=native.applicable&&native.topology_ok;
                        evidence.d025_foundation_npc_branch_proof=native;
                    end
                    if branchProof
                        msg='PHYSICAL_PATH_PROVED_BY_D025_FOUNDATION_NPC_BRANCH_INCIDENCE';
                    else
                        ok=false; msg='PHYSICAL_PATH_VIA_IS_REACHABLE_BUT_NOT_A_REQUIRED_CUT';
                    end
                end
            case 'transformer_phase_diversity'
                [ok,msg,evidence]=transformer_phase_diversity(modelName,getnum(rc,'k',2));
            case 'forbid_universal_bridge'
                present=P.has_mask(modelName,{'universal bridge'});ok=~present;
                if present,msg='Universal Bridge detected';else,msg='Universal Bridge absent';end
            otherwise, msg=['UNKNOWN_PRIMITIVE:' prim];
        end
        if getbool(rc,'negate',false), ok=~ok; end
    catch e
        ok=false; msg=['STRUCT_ERROR:' strtrim(e.message)];
    end
    vals(end+1)=double(ok); weights(end+1)=w; mandatory(end+1)=double(must); %#ok<AGROW>
    reports(end+1)=struct('id',string(id),'prim',string(prim),'ok',logical(ok), ...
        'mandatory',logical(must),'weight',w,'detail',string(msg),'evidence',evidence); %#ok<AGROW>
end
score=sum(vals.*weights)/max(sum(weights),eps);
mandatoryOk=all(vals(mandatory>0)>0);
detail=strjoin(arrayfun(@(r) sprintf('%s:%s%s',r.id,r.prim,tern(r.ok,'+','-')),reports,'UniformOutput',false),',');
end

function ok=svpwm_verified(modelName)
% Do not accept generic "PWM Generator" or "two-level" naming.
P=sat_prims(); named=P.has_name_or_mask(modelName,{'svpwm','space\s*vector','space-vector','(^|[\W_])svm([\W_]|$)'});
minmax=P.has_blocktype(modelName,{'Sin'}) && P.count_blocktype(modelName,'MinMax')>=2 && P.has_blocktype(modelName,{'RelationalOperator'});
sector=P.has_blocktype(modelName,{'Trigonometry'}) && (P.has_blocktype(modelName,{'Lookup_n-D'})||P.has_blocktype(modelName,{'MultiPortSwitch'})||P.has_blocktype(modelName,{'SwitchCase'}));
ok=named||minmax||sector;
end

function [ok,msg,evidence]=transformer_phase_diversity(modelName,kMin)
% Count only connection groups and actual phase-angle parameters.  Winding
% voltage/impedance vectors are not evidence of phase diversity.
blks=find_system(modelName,'LookUnderMasks','on','FollowLinks','on','Type','Block');
phaseVals=[]; connectionVals=strings(0,1); ntr=0; effectiveGroups=0;
observations=struct('block',{},'parameter',{},'kind',{},'raw',{},'values',{});
for i=1:numel(blks)
    mt=''; try, mt=lower(string(get_param(blks{i},'MaskType'))); catch, end
    if ~contains(mt,'transformer'), continue; end; ntr=ntr+1;blockGroups=1;
    dp=[]; try, dp=get_param(blks{i},'DialogParameters'); catch, end
    if isempty(dp), continue; end
    fs=fieldnames(dp);
    for q=1:numel(fs)
        name=lower(string(fs{q})); raw="";
        try, raw=string(get_param(blks{i},fs{q})); catch, end
        if strlength(strtrim(raw))==0, continue; end
        if name=="pulsenumber"&&contains(mt,'phase-shifting')
            groups=pulse_group_count(raw);
            if groups>0
                blockGroups=max(blockGroups,groups);
                angles=(0:groups-1)*(60/groups);phaseVals=[phaseVals angles]; %#ok<AGROW>
                observations(end+1)=make_observation(blks{i},fs{q},'pulse-number',raw, ... %#ok<AGROW>
                    strjoin(string(angles),"|"));
            end
        elseif contains(name,'connection')||contains(name,'vector_group')||contains(name,'vectorgroup')
            [angles,group]=connection_observation(raw);
            phaseVals=[phaseVals angles]; %#ok<AGROW>
            if strlength(group)>0, connectionVals(end+1)=group; end %#ok<AGROW>
            observations(end+1)=make_observation(blks{i},fs{q},'connection',raw, ...
                strjoin([string(angles),group],"|")); %#ok<AGROW>
        elseif contains(name,'phase')||contains(name,'shift')||contains(name,'angle')||contains(name,'clock')
            angles=numeric_literals(raw);
            phaseVals=[phaseVals angles]; %#ok<AGROW>
            observations(end+1)=make_observation(blks{i},fs{q},'phase',raw, ...
                strjoin(string(angles),"|")); %#ok<AGROW>
        elseif (contains(mt,'phase-shifting')||contains(mt,'zigzag'))&&name=="secondaryvoltage"
            nums=numeric_literals(raw);
            if numel(nums)>=2
                angle=nums(end); phaseVals(end+1)=angle; %#ok<AGROW>
                observations(end+1)=make_observation(blks{i},fs{q},'phase-vector',raw,string(angle)); %#ok<AGROW>
            end
        end
    end
    effectiveGroups=effectiveGroups+blockGroups;
end

phaseVals=normalize_angles(phaseVals);
phaseVals=unique(phaseVals,'stable');
connectionVals=unique(connectionVals(strlength(connectionVals)>0),'stable');
diversity=max(numel(phaseVals),numel(connectionVals));
ok=effectiveGroups>=kMin&&diversity>=kMin;
msg=sprintf(['transformers=%d effective_groups=%d distinct_phase_values=%d ' ...
    'distinct_connection_groups=%d diversity=%d required=%g'], ...
    ntr,effectiveGroups,numel(phaseVals),numel(connectionVals),diversity,kMin);
evidence=struct('transformer_count',ntr,'distinct_phase_values',phaseVals, ...
    'distinct_connection_values',connectionVals,'diversity_count',diversity, ...
    'effective_transformer_groups',effectiveGroups,'required',kMin,'observations',observations);
end

function n=pulse_group_count(raw)
s=lower(char(string(raw)));n=0;
if contains(s,'twentyfour')||~isempty(regexp(s,'(?:^|\D)24(?:\D|$)','once')),n=4;
elseif contains(s,'eighteen')||~isempty(regexp(s,'(?:^|\D)18(?:\D|$)','once')),n=3;
elseif contains(s,'twelve')||~isempty(regexp(s,'(?:^|\D)12(?:\D|$)','once')),n=2;
end
end

function o=make_observation(block,param,kind,raw,values)
o=struct('block',string(block),'parameter',string(param),'kind',string(kind), ...
    'raw',string(raw),'values',string(values));
end

function [angles,group]=connection_observation(raw)
s=lower(strtrim(string(raw))); angles=[]; group="";
deg=regexp(char(s),'([-+]?\d+(?:\.\d+)?)\s*deg','tokens');
if ~isempty(deg)
    angles=cellfun(@(x) str2double(x{1}),deg);
elseif ~isempty(regexp(char(s),'delta\s*d11','once'))
    angles=30;
elseif ~isempty(regexp(char(s),'delta\s*d1(?:\D|$)','once'))
    angles=-30;
elseif ~isempty(regexp(char(s),'^y(?:n|g)?$','once'))
    angles=0;
end
if ~isempty(regexp(char(s),'^y(?:n|g)?$','once'))
    group="y0";
elseif contains(s,'delta d11')
    group="delta_d11";
elseif ~isempty(regexp(char(s),'delta\s*d1(?:\D|$)','once'))
    group="delta_d1";
else
    group=regexprep(s,'[^a-z0-9+-]+','_');
    group=strip(group,'_');
end
end

function nums=numeric_literals(raw)
tokens=regexp(char(string(raw)),'[-+]?(?:\d*\.?\d+)(?:[eE][-+]?\d+)?','match');
if isempty(tokens), nums=[]; else, nums=cellfun(@str2double,tokens); end
nums=nums(isfinite(nums));
end

function vals=normalize_angles(vals)
if isempty(vals), return; end
vals=mod(double(vals)+180,360)-180;
vals(abs(vals)<1e-9)=0;
vals=round(vals*1e9)/1e9;
end

function [n,paths]=count_capacitors(modelName)
blocks=find_system(modelName,'LookUnderMasks','on','FollowLinks','on','Type','Block'); paths=strings(0,1);
for i=1:numel(blocks)
    b=blocks{i}; name=lower(string(get_param(b,'Name'))); mt=""; rb=""; bt="";
    try,mt=lower(string(get_param(b,'MaskType')));catch,end
    try,rb=lower(string(get_param(b,'ReferenceBlock')));catch,end
    try,bt=lower(string(get_param(b,'BlockType')));catch,end
    desc=name+"|"+mt+"|"+rb+"|"+bt; isCap=~isempty(regexpi(char(desc),'(^|[/| _-])capacitor([/| _-]|$)','once'));
    branchType=""; try,branchType=upper(strtrim(string(get_param(b,'BranchType'))));catch,end
    if branchType=="C", isCap=true; end
    if isCap, paths(end+1)=string(b); end %#ok<AGROW>
end
paths=unique(paths,'stable'); n=numel(paths);
end

function n=numel_any(a), n=numel(a); end
function e=elem(a,i), if iscell(a), e=a{i}; else, e=a(i); end, end
function v=getnum(s,f,d), v=d; if isfield(s,f)&&~isempty(s.(f))&&isnumeric(s.(f)), v=double(s.(f)); end, end
function v=getstr(s,f,d), v=d; if isfield(s,f)&&~isempty(s.(f)), v=char(string(s.(f))); end, end
function v=getbool(s,f,d), v=d; if isfield(s,f)&&~isempty(s.(f)), v=logical(s.(f)); end, end
function out=getstrings(s,f)
out={}; if ~isfield(s,f)||isempty(s.(f)), return; end
x=s.(f); if iscell(x), out=cellfun(@(z) char(string(z)),x,'UniformOutput',false); else, out=cellstr(string(x)); end
end
function s=tern(c,a,b), if c,s=a;else,s=b;end,end
