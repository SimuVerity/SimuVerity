function reports = sat_prepare_golden(modelName, spec)
%SAT_PREPARE_GOLDEN Expose golden outputs with explicit tap diagnostics.

reports=struct('name',{},'ok',{},'tap_by',{},'source_block',{},'message',{});
tapField='golden_tap'; if ~isfield(spec,tapField), tapField='golden_tap'; end
if ~isfield(spec,tapField)
    for i=1:numel_any(spec.outputs)
        o=elem(spec.outputs,i); reports(end+1)=row(o.name,false,'','',"TAP_MAP_MISSING"); %#ok<AGROW>
    end
    return;
end
tapMap=spec.(tapField);

for i=1:numel_any(spec.outputs)
    o=elem(spec.outputs,i); oname=char(string(o.name));
    if ~isfield(tapMap,oname)
        reports(end+1)=row(oname,false,'','',"TAP_MISSING"); continue; %#ok<AGROW>
    end
    tap=tapMap.(oname); by=lower(char(string(tap.by))); src=-1; parent=''; sourceBlock=''; msg='';
    try
        switch by
            case {'block_output','block'}
                path=char(string(tap.path)); port=getnum(tap,'port',1);
                if getSimulinkBlockHandle(path)<0, error('block not found: %s',path); end
                ph=get_param(path,'PortHandles'); if numel(ph.Outport)<port, error('output port %d missing',port); end
                src=ph.Outport(port); parent=get_param(path,'Parent'); sourceBlock=path;
            case {'block_input','scope_path'}
                path=char(string(tap.path)); port=getnum(tap,'port',1);
                if getSimulinkBlockHandle(path)<0, error('block not found: %s',path); end
                ph=get_param(path,'PortHandles'); if numel(ph.Inport)<port, error('input port %d missing',port); end
                ln=get_param(ph.Inport(port),'Line'); if isempty(ln)||ln<0, error('input port %d is unconnected',port); end
                src=get_param(ln,'SrcPortHandle'); parent=get_param(path,'Parent'); sourceBlock=get_param(src,'Parent');
            case 'port_regex'
                pattern=char(string(tap.block)); port=getnum(tap,'port',1);
                cand=find_system(modelName,'LookUnderMasks','on','FollowLinks','on','Type','Block'); hit='';
                for q=1:numel(cand), if ~isempty(regexpi(cand{q},pattern,'once')), if ~isempty(hit), error('regex tap is ambiguous'); end, hit=cand{q}; end, end
                if isempty(hit), error('regex tap not found'); end
                ph=get_param(hit,'PortHandles'); if numel(ph.Outport)<port, error('output port missing'); end
                src=ph.Outport(port); parent=get_param(hit,'Parent'); sourceBlock=hit;
            case 'scope'
                if ~isfield(spec,'allow_source_scope_tap')||~logical(spec.allow_source_scope_tap)
                    error('source global scope ordinal is forbidden by the public contract');
                end
                scopes=find_system(modelName,'LookUnderMasks','on','FollowLinks','on','BlockType','Scope');
                idx=getnum(tap,'index',1); port=getnum(tap,'port',1);
                if numel(scopes)<idx, error('scope ordinal missing'); end
                ph=get_param(scopes{idx},'PortHandles'); if numel(ph.Inport)<port, error('scope input missing'); end
                ln=get_param(ph.Inport(port),'Line'); if isempty(ln)||ln<0, error('scope input unconnected'); end
                src=get_param(ln,'SrcPortHandle'); parent=get_param(scopes{idx},'Parent'); sourceBlock=get_param(src,'Parent');
            otherwise
                error('unsupported tap type: %s',by);
        end
        if src<0||isempty(parent), error('tap did not resolve a source port'); end
        sink=[parent '/__v4_out_' matlab.lang.makeValidName(oname)];
        reuse=false;
        if getSimulinkBlockHandle(sink)>=0
            if string(get_param(sink,'BlockType'))=="ToWorkspace"
                % Goldens may already contain evaluator-owned taps from a
                % previous fresh replay.  Reuse an exact source binding so
                % preparation is idempotent; deleting only the sink can
                % leave a branched source line and make re-attachment fail.
                set_param(sink,'VariableName',oname,'SaveFormat','Timeseries');
                iph=get_param(sink,'PortHandles');ln=get_param(iph.Inport(1),'Line');
                if ~isempty(ln)&&ln>=0&&get_param(ln,'SrcPortHandle')==src
                    reuse=true;
                elseif ~isempty(ln)&&ln>=0
                    delete_line(ln);
                end
            else
                delete_block(sink);
            end
        end
        if getSimulinkBlockHandle(sink)<0
            add_block('simulink/Sinks/To Workspace',sink, ...
                'VariableName',oname,'SaveFormat','Timeseries');
        end
        iph=get_param(sink,'PortHandles');
        if ~reuse,add_line(parent,src,iph.Inport(1),'autorouting','on');end
        reports(end+1)=row(oname,true,by,sourceBlock,"OK"); %#ok<AGROW>
    catch e
        msg=string(strtrim(e.message)); reports(end+1)=row(oname,false,by,sourceBlock,msg); %#ok<AGROW>
    end
end
end

function r=row(name,ok,by,source,msg)
r=struct('name',string(name),'ok',logical(ok),'tap_by',string(by),'source_block',string(source),'message',string(msg));
end
function n=numel_any(a), n=numel(a); end
function e=elem(a,i), if iscell(a), e=a{i}; else, e=a(i); end, end
function v=getnum(s,f,d), v=d; if isfield(s,f)&&~isempty(s.(f))&&isnumeric(s.(f)), v=double(s.(f)); end, end
