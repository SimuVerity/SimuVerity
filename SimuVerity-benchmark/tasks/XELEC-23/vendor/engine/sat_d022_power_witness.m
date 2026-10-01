function witness=sat_d022_power_witness(modelName,varName)
%SAT_D022_POWER_WITNESS Verify a physical three-phase power signal.
% A legal D022 power output is either an exact MathWorks three-phase power
% measurement, or a restricted three-phase V/I computation backed by exact
% MathWorks measurement identities.  User names and MaskType alone are
% never trusted.

witness=empty_witness(varName);
sink=workspace_sink(modelName,varName);
if strlength(sink)==0,witness.detail="TO_WORKSPACE_NOT_UNIQUE";return;end
trace=sat_trace_upstream(modelName,char(sink),1,24);
witness.trace=trace;
if isempty(trace),witness.detail="EMPTY_UPSTREAM_TRACE";return;end

% Preserve the established native Power (3ph)/Power Measurement route.
powerBlocks=strings(0,1);
for i=1:numel(trace)
    b=string(trace(i).path);s=sat_provenance_semantic(char(b));
    if s.trusted&&s.kind=="measurement"&&contains(s.semantic,"power measurement")
        powerBlocks(end+1,1)=b; %#ok<AGROW>
    end
end
powerBlocks=topmost(unique(powerBlocks,'stable'));
if numel(powerBlocks)==1
    % Exact native measurement identity plus the existing output-contract
    % trace preserves the established legal route, including source
    % hierarchy/routing wrappers used by the golden model.
    witness.ok=true;witness.kind="native_power_measurement";
    witness.endpoint=powerBlocks(1);witness.detail="OK";return;
elseif numel(powerBlocks)>1
    witness.detail="PHYSICAL_POWER_ENDPOINT_AMBIGUOUS";return;
end

% Derived routes: vector DotProduct/Sum(Product), or three explicit
% per-phase products followed by an all-positive Sum.
[endpoint,sensors,kind,detail]=derived_endpoint(trace);
if strlength(endpoint)==0,witness.detail=detail;return;end
if ~post_chain_allowed(modelName,sink,endpoint)
    witness.detail="NONTRANSPARENT_POST_POWER_CHAIN";return;
end
witness.ok=true;witness.kind=kind;witness.endpoint=endpoint;
witness.sensor_blocks=sensors;witness.detail="OK";
end

function [endpoint,sensors,kind,detail]=derived_endpoint(trace)
endpoint="";sensors=strings(0,1);kind="";detail="POWER_COMPUTATION_NOT_FOUND";
blocks=unique(string({trace.path}),'stable');
hits=struct('endpoint',{},'sensors',{},'kind',{},'origins',{});
for b=blocks(:)'
    bt=lower(string(getp(b,'BlockType')));
    if bt=="dotproduct"
        [ok,s,o,route]=vector_power_pair(b);
        if ok,hits(end+1)=row(b,s,route+"_dot_product",o);end %#ok<AGROW>
    elseif is_sum_block(bt)
        p=single_source_block(b);
        if strlength(p)>0&&lower(string(getp(p,'BlockType')))=="product"
            [ok,s,o,route]=vector_power_pair(p);
            if ok,hits(end+1)=row(b,s,route+"_product_then_sum",o);end %#ok<AGROW>
        elseif bt=="sum"
            [ok,s,o]=per_phase_multiply_sum(b);
            if ok,hits(end+1)=row(b,s,"single_phase_multiply_add",o);end %#ok<AGROW>
        end
    end
end
if isempty(hits),return;end
keys=strings(1,numel(hits));
for i=1:numel(hits)
    keys(i)=hits(i).endpoint+"|"+strjoin(sort(string(hits(i).origins(:))),"|");
end
[~,ix]=unique(keys,'stable');hits=hits(ix);
if numel(hits)~=1,detail="POWER_COMPUTATION_AMBIGUOUS";return;end
endpoint=hits.endpoint;sensors=string(hits.sensors(:));kind=hits.kind;detail="OK";
end

function r=row(endpoint,sensors,kind,origins)
r=struct('endpoint',string(endpoint),'sensors',{string(sensors(:))}, ...
    'kind',string(kind),'origins',{string(origins(:))});
end

function [ok,sensors,origins,route]=vector_power_pair(block)
ok=false;sensors=strings(0,1);origins=strings(0,1);route="";
ph=[];try,ph=get_param(char(block),'PortHandles');catch,return;end
if ~isfield(ph,'Inport')||numel(ph.Inport)~=2,return;end
b=repmat(empty_bundle(),1,2);
for i=1:2,src=source_from_inport(ph.Inport(i));if src<0,return;end
    b(i)=measurement_bundle(src);if ~b(i).ok,return;end
end
if ~roles_are_vi(b(1).role,b(2).role),return;end
if b(1).mode=="combined_vi"||b(2).mode=="combined_vi"
    if ~(b(1).mode=="combined_vi"&&b(2).mode=="combined_vi" ...
            &&numel(b(1).sensors)==1&&isequal(b(1).sensors,b(2).sensors))
        return;
    end
    route="vi";
else
    route="single_phase_vi";
end
origins=[b(1).origins(:);b(2).origins(:)];
if numel(unique(origins))~=numel(origins),return;end
sensors=unique([b(1).sensors(:);b(2).sensors(:)],'stable');ok=true;
end

function yes=trusted_complete_three_phase_vi(block)
yes=false;if strlength(string(block))==0||getSimulinkBlockHandle(char(block))<0,return;end
s=sat_provenance_semantic(char(block));
if ~(s.trusted&&s.kind=="measurement"&&contains(s.semantic,"three-phase vi measurement")),return;end
ph=[];try,ph=get_param(char(block),'PortHandles');catch,return;end
if ~isfield(ph,'LConn')||~isfield(ph,'RConn')||numel(ph.LConn)~=3||numel(ph.RConn)~=3,return;end
ports=[ph.LConn(:);ph.RConn(:)];yes=all(arrayfun(@port_connected,ports));
end

function b=measurement_bundle(src)
b=empty_bundle();parent="";outNo=0;
try,parent=string(get_param(src,'Parent'));outNo=double(get_param(src,'PortNumber'));catch,return;end
if trusted_complete_three_phase_vi(parent)&&any(outNo==[1 2])
    b.ok=true;b.mode="combined_vi";b.sensors=parent;
    if outNo==1,b.role="voltage";else,b.role="current";end
    b.origins=parent+"#"+b.role;return;
end
bt=lower(string(getp(parent,'BlockType')));
if ~any(bt==["mux","vectorconcatenate"]),return;end
ph=[];try,ph=get_param(char(parent),'PortHandles');catch,return;end
if ~isfield(ph,'Inport')||numel(ph.Inport)~=3,return;end
parts=repmat(empty_scalar(),1,3);
for i=1:3
    p=source_from_inport(ph.Inport(i));if p<0,return;end
    parts(i)=scalar_measurement(p);if ~parts(i).ok,return;end
end
roles=string({parts.role});if numel(unique(roles))~=1,return;end
origins=string({parts.origin});if numel(unique(origins))~=3,return;end
phases=string({parts.phase});known=phases(strlength(phases)>0);
if ~isempty(known)&&(numel(known)~=3||~isequal(sort(known),["a","b","c"])),return;end
b.ok=true;b.role=roles(1);b.mode="scalar_bundle";
b.sensors=unique(string({parts.sensor}),'stable');b.origins=origins;
end

function s=scalar_measurement(src)
s=empty_scalar();parent="";try,parent=string(get_param(src,'Parent'));catch,return;end
semantic=sat_provenance_semantic(char(parent));
if semantic.trusted&&semantic.kind=="measurement" ...
        &&~contains(semantic.semantic,"three-phase vi measurement") ...
        &&single_phase_sensor_connected(parent)
    if contains(semantic.semantic,"voltage measurement")
        s.ok=true;s.role="voltage";
    elseif contains(semantic.semantic,"current measurement")
        s.ok=true;s.role="current";
    else,return;end
    s.sensor=parent;s.origin=parent;return;
end
[ok,machine,phase,origin]=machine_current_selector(src);
if ok,s.ok=true;s.role="current";s.sensor=machine;s.phase=phase;s.origin=origin;end
end

function [ok,machine,phase,origin]=machine_current_selector(src)
ok=false;machine="";phase="";origin="";selector="";outNo=0;
try,selector=string(get_param(src,'Parent'));outNo=double(get_param(src,'PortNumber'));catch,return;end
if lower(string(getp(selector,'BlockType')))~="busselector",return;end
labels=strip(split(string(getp(selector,'OutputSignals')),','));
if outNo<1||outNo>numel(labels),return;end
label=lower(labels(outNo));
if any(label==["ias","ibs","ics"]),phase=extractBetween(label,2,2);
elseif any(label==["ia","ib","ic"]),phase=extractAfter(label,1);
elseif any(label==["is_a","is_b","is_c","i_a","i_b","i_c"]),phase=extractAfter(label,"_");
else,return;end
root=bdroot(char(selector));
if isnumeric(root),model=string(get_param(root,'Name'));else,model=string(root);end
trace=sat_trace_upstream(char(model),char(selector),1,12);machines=strings(0,1);
for i=1:numel(trace)
    q=sat_provenance_semantic(char(trace(i).path));
    if q.trusted&&q.kind=="measurement"&&contains(q.semantic,"machine measurement")
        machines(end+1,1)=string(trace(i).path); %#ok<AGROW>
    end
end
machines=unique(machines,'stable');if numel(machines)~=1,return;end
machine=machines(1);if ~machine_boundary_connected(machine),machine="";return;end
origin=machine+"#"+label;ok=true;
end

function [ok,sensors,origins]=per_phase_multiply_sum(block)
ok=false;sensors=strings(0,1);origins=strings(0,1);
ph=[];try,ph=get_param(char(block),'PortHandles');catch,return;end
if ~isfield(ph,'Inport')||numel(ph.Inport)~=3||~all_positive_sum(block),return;end
v=repmat(empty_scalar(),1,3);c=repmat(empty_scalar(),1,3);products=strings(1,3);
for i=1:3
    src=source_from_inport(ph.Inport(i));if src<0,return;end
    try,p=string(get_param(src,'Parent'));catch,return;end
    if lower(string(getp(p,'BlockType')))~="product"||~all_multiply_product(p),return;end
    products(i)=p;pp=get_param(char(p),'PortHandles');if numel(pp.Inport)~=2,return;end
    a=scalar_measurement(source_from_inport(pp.Inport(1)));
    z=scalar_measurement(source_from_inport(pp.Inport(2)));
    if ~a.ok||~z.ok||~roles_are_vi(a.role,z.role),return;end
    if a.role=="voltage",v(i)=a;c(i)=z;else,v(i)=z;c(i)=a;end
end
if numel(unique(products))~=3,return;end
vo=string({v.origin});co=string({c.origin});
if numel(unique(vo))~=3||numel(unique(co))~=3||~isempty(intersect(vo,co)),return;end
vp=string({v.phase});cp=string({c.phase});
if ~phase_set_valid(vp)||~phase_set_valid(cp),return;end
origins=[vo(:);co(:)];sensors=unique([string({v.sensor})';string({c.sensor})'],'stable');ok=true;
end

function yes=roles_are_vi(a,b)
yes=(a=="voltage"&&b=="current")||(a=="current"&&b=="voltage");
end

function yes=phase_set_valid(phases)
known=phases(strlength(phases)>0);yes=isempty(known) ...
    ||(numel(known)==3&&isequal(sort(known),["a","b","c"]));
end

function yes=single_phase_sensor_connected(block)
ports=connection_ports(block);yes=numel(ports)==2&&all(arrayfun(@port_connected,ports));
end

function yes=machine_boundary_connected(block)
ports=connection_ports(block);yes=numel(ports)>=3&&all(arrayfun(@port_connected,ports));
end

function ports=connection_ports(block)
ports=[];ph=[];try,ph=get_param(char(block),'PortHandles');catch,return;end
for f={'LConn','RConn'}
    if isfield(ph,f{1})&&~isempty(ph.(f{1})),ports=[ports;ph.(f{1})(:)];end %#ok<AGROW>
end
end

function yes=all_positive_sum(block)
raw=lower(strtrim(string(getp(block,'Inputs'))));
yes=raw=="3"||~isempty(regexp(char(raw),'^\+{3}$','once'));
end

function yes=all_multiply_product(block)
raw=lower(strtrim(string(getp(block,'Inputs'))));
yes=raw=="2"||(~contains(raw,"/")&&~isempty(regexp(char(raw),'^\*{2}$','once')));
end

function b=empty_bundle()
b=struct('ok',false,'role',"",'mode',"",'sensors',strings(0,1), ...
    'origins',strings(0,1));
end

function s=empty_scalar()
s=struct('ok',false,'role',"",'sensor',"",'origin',"",'phase',"");
end

function yes=post_chain_allowed(modelName,sink,endpoint)
% Follow the unique signal path backwards.  After physical power has been
% formed, only unity-DC-gain filtering, sign, delay and representation
% conversion may intervene before logging.
yes=false;current=string(sink);seen=strings(0,1);
for depth=1:24
    upstream=single_source_block(current);if strlength(upstream)==0,return;end
    if upstream==endpoint,yes=true;return;end
    if ~startsWith(upstream,string(modelName)+"/")||any(seen==upstream),return;end
    seen(end+1,1)=upstream; %#ok<AGROW>
    if ~allowed_post_block(upstream),return;end
    current=upstream;
end
end

function yes=allowed_post_block(block)
yes=false;bt=lower(string(getp(block,'BlockType')));
if any(bt==["datatypeconversion","signalconversion","ratetransition", ...
        "unitdelay","delay","memory"]),yes=true;return;end
if bt=="gain"
    g=resolve_scalar_token(getp(block,'Gain'),block);
    yes=isfinite(g)&&abs(abs(g)-1)<=1e-12;return;
end
if any(bt==["discretetransferfcn","transferfcn","discretefilter"])
    yes=unity_dc_filter(block,bt);return;
end
end

function yes=unity_dc_filter(block,bt)
yes=false;num=parse_bound_vector(getp(block,'Numerator'),block);
den=parse_bound_vector(getp(block,'Denominator'),block);
if isempty(num)||isempty(den),return;end
if bt=="transferfcn"
    if abs(den(end))<=eps,return;end;gain=num(end)/den(end);
else
    if abs(sum(den))<=eps,return;end;gain=sum(num)/sum(den);
end
yes=isfinite(gain)&&abs(gain-1)<=0.02;
end

function v=parse_bound_vector(text,block)
v=[];s=char(strtrim(string(text)));if isempty(s),return;end
if ~isempty(regexp(s,'[^\[\]\s,;.+\-0-9A-Za-z_]','once')),return;end
tokens=regexp(regexprep(s,'[\[\],;]',' '),'\S+','match');if isempty(tokens),return;end
values=zeros(1,numel(tokens));
for i=1:numel(tokens)
    values(i)=resolve_scalar_token(tokens{i},block);if ~isfinite(values(i)),return;end
end
v=values;
end

function value=resolve_scalar_token(text,block)
value=NaN;token=strtrim(string(text));if strlength(token)==0,return;end
literal=str2double(token);if isfinite(literal),value=literal;return;end
if isempty(regexp(char(token),'^[A-Za-z]\w*$','once')),return;end
try,resolved=slResolve(char(token),char(block));catch,return;end
if isnumeric(resolved)&&isreal(resolved)&&isscalar(resolved)&&isfinite(resolved)
    value=double(resolved);
end
end

function tf=is_sum_block(bt)
tf=any(bt==["sum","sumofelements"]);
end

function block=single_source_block(block)
block=string(block);ph=[];try,ph=get_param(char(block),'PortHandles');catch,block="";return;end
if ~isfield(ph,'Inport')||numel(ph.Inport)~=1,block="";return;end
src=source_from_inport(ph.Inport(1));if src<0,block="";return;end
try,block=string(get_param(src,'Parent'));catch,block="";end
end

function p=source_from_inport(inport)
p=-1;try,ln=get_param(inport,'Line');if isempty(ln)||ln<0,return;end
    p=get_param(ln,'SrcPortHandle');if isempty(p),p=-1;end
catch,p=-1;end
end

function yes=port_connected(port)
yes=false;try,ln=get_param(port,'Line');yes=~isempty(ln)&&all(double(ln)>=0);catch,end
end

function sink=workspace_sink(modelName,varName)
sink="";blocks=find_system(modelName,'LookUnderMasks','on','FollowLinks','on','BlockType','ToWorkspace');hits=strings(0,1);
for i=1:numel(blocks),if string(strtrim(getp(blocks{i},'VariableName')))==string(varName),hits(end+1)=string(blocks{i});end,end %#ok<AGROW>
if numel(hits)==1,sink=hits;end
end

function out=topmost(blocks)
blocks=string(blocks(:));out=strings(0,1);
for i=1:numel(blocks)
    if ~any(startsWith(blocks(i),blocks((1:numel(blocks))~=i)+"/")),out(end+1,1)=blocks(i);end %#ok<AGROW>
end
end

function value=getp(block,param)
value='';try,value=get_param(char(block),param);catch,end
if isnumeric(value),value=num2str(value);end
end

function w=empty_witness(name)
w=struct('name',string(name),'ok',false,'kind',"",'endpoint',"", ...
    'sensor_blocks',strings(0,1),'detail',"UNINITIALIZED",'trace',struct([]));
end
