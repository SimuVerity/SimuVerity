function P = sat_prims()
% Reusable scoring primitives (SINGLE SOURCE). Returns a struct of function handles so
% specs/engine/golden-checks all share one implementation. Replaces the copies that were
% inlined in baselineA_score / baselineB_score / golden_struct_check.
    P.has_mask            = @has_mask;
    P.count_mask          = @count_mask;
    P.has_blocktype       = @has_blocktype;
    P.count_blocktype     = @count_blocktype;
    P.has_name_or_mask    = @has_name_or_mask;
    P.has_integral_action = @has_integral_action;
    P.svpwm_panel         = @svpwm_panel;
    P.three_phase_source  = @three_phase_source;
    P.three_phase_bridge  = @three_phase_bridge;
    P.has_power_device    = @has_power_device;
    P.steady              = @steady;
end

% ---- representation-invariant power-semiconductor recognizer. Accepts a device
%      (diode / thyristor / IGBT / MOSFET / ideal switch / GTO ...) built EITHER as
%      (A) a discrete block whose mask names the device, OR
%      (B) a bridge block (Universal Bridge / Three-Level Bridge ...) whose 'Device'
%      parameter is set to one of the requested devices.
%      Stays device-specific: an IGBT query is NOT satisfied by a Thyristor/Diode bridge. ----
function b = has_power_device(name, devices)
    devs = reshape(string(devices),1,[]); b=false;
    blks = find_system(name,'LookUnderMasks','on','FollowLinks','on','Type','Block');
    for k=1:numel(blks)
        mt=''; try, mt=get_param(blks{k},'MaskType'); catch, end
        mt=lower(string(mt)); if strlength(mt)==0, continue; end
        for d=devs, dd=lower(d);                                                  % (A) device named in mask
            if ~contains(dd,'bridge') && strlength(dd)>0 && contains(mt,dd), b=true; return; end
        end
        if contains(mt,'bridge')                                                  % (B) bridge w/ Device param
            dv=''; try, dv=get_param(blks{k},'Device'); catch, end
            dv=lower(string(dv));
            for d=devs, dd=lower(d); if ~contains(dd,'bridge') && strlength(dd)>0 && contains(dv,dd), b=true; return; end, end
        end
    end
end

% ---- per-task composite recognizer: SVPWM (named OR min-max common-mode OR sector) ----
function ok = svpwm_panel(name)
    namedSV  = has_name_or_mask(name,{'svpwm','space vector','space-vector','svm','pwm generator','two-level'});
    % min-max common-mode injection (SVPWM-equivalent). The 3-phase reference can come from THREE
    % Sin blocks OR ONE vectorized Sin (Phase=[0 -2pi/3 2pi/3]) -- audit caught the old 'Sin>=3'
    % heuristic false-failing a legit vectorized build; requiring the max+min PAIR (>=2 MinMax)
    % keeps the signature specific to common-mode injection.
    minmaxSV = has_blocktype(name,{'Sin'}) && (count_blocktype(name,'MinMax')>=2) && has_blocktype(name,{'RelationalOperator'});
    sectorSV = has_blocktype(name,{'Trigonometry'}) && (has_blocktype(name,{'Lookup_n-D'}) || has_blocktype(name,{'MultiPortSwitch'}) || has_blocktype(name,{'SwitchCase'}));
    ok = namedSV || minmaxSV || sectorSV;
end

% ---- representation-invariant 3-phase AC source: 3+ single-phase 'AC Voltage Source'
%      blocks OR one 'Three-Phase Source' block -- both are valid three-phase inputs. ----
function b = three_phase_source(name)
    b = count_mask(name,{'AC Voltage Source'})>=3 || has_mask(name,{'Three-Phase Source'});
    if b, return; end

    % Native Simscape Electrical uses the reversed, newline-formatted mask
    % label "Voltage Source (Three-Phase)".  Accept that representation
    % only when the block is still linked to the exact ee_lib source.  A
    % user-named or user-masked Subsystem therefore cannot manufacture this
    % identity, while arbitrary renaming of the genuine library block is
    % harmless.
    blks = find_system(name,'LookUnderMasks','on','FollowLinks','on','Type','Block');
    for k=1:numel(blks)
        mt=""; rb="";
        try, mt=normalise_trusted_text(get_param(blks{k},'MaskType')); catch, end
        try, rb=normalise_trusted_text(get_param(blks{k},'ReferenceBlock')); catch, end
        nativeMask = mt=="voltage source (three-phase)";
        nativeRef = contains(rb,"ee_lib/sources/voltage source (three-phase)");
        if nativeMask && nativeRef, b=true; return; end
    end
end

function out = normalise_trusted_text(value)
    out=lower(regexprep(strtrim(string(value)),'\s+',' '));
    out=replace(out,'\','/');
end

% ---- representation-invariant THREE-PHASE power stage: >=6 discrete power-semiconductor
%      blocks (3 legs x 2 switches/diodes), OR a bridge block with >=3 arms (3-phase bridge).
%      Rejects a single-phase stage (2-4 devices / 1-2 arm bridge). ----
function b = three_phase_bridge(name)
    b=false;
    blks = find_system(name,'LookUnderMasks','on','FollowLinks','on','Type','Block');
    ndev=0;
    for k=1:numel(blks)
        mt=''; try, mt=lower(string(get_param(blks{k},'MaskType'))); catch, end
        if contains(mt,'igbt')||contains(mt,'mosfet')||contains(mt,'diode')||contains(mt,'thyristor')||contains(mt,'gto')
            ndev=ndev+1;
        end
    end
    if ndev>=6, b=true; return; end                                        % (A) >=6 discrete devices
    for k=1:numel(blks)
        mt=''; try, mt=lower(string(get_param(blks{k},'MaskType'))); catch, end
        if contains(mt,'bridge')
            na=NaN; try, na=str2double(string(get_param(blks{k},'Arms'))); catch, end
            if ~isnan(na) && na>=3, b=true; return; end                    % (B) bridge with >=3 arms
        end
    end
end

% ---- structural primitives ----
function n = count_mask(name, pats)
    blks = find_system(name,'LookUnderMasks','on','FollowLinks','on','Type','Block'); n=0;
    for k=1:numel(blks)
        mt=''; try, mt=get_param(blks{k},'MaskType'); catch, end
        mt=lower(string(mt)); if strlength(mt)==0, continue; end
        for p=reshape(string(pats),1,[]), if ~isempty(regexp(mt,lower(p),'once')), n=n+1; break; end, end
    end
end
function b = has_mask(name,pats), b = count_mask(name,pats)>0; end
function b = has_blocktype(name, types)
    b=false; for ty=reshape(string(types),1,[]), if ~isempty(find_system(name,'LookUnderMasks','on','FollowLinks','on','BlockType',char(ty))), b=true; return; end, end
end
function n = count_blocktype(name, bt)
    n = numel(find_system(name,'LookUnderMasks','on','FollowLinks','on','BlockType',char(bt)));
end
function b = has_name_or_mask(name, pats)
    blks = find_system(name,'LookUnderMasks','on','FollowLinks','on','Type','Block'); b=false;
    for k=1:numel(blks)
        s = lower(string(get_param(blks{k},'Name')) + "|" + string(get_param(blks{k},'BlockType')));
        try, s = s + "|" + lower(string(get_param(blks{k},'MaskType'))); catch, end
        for p=reshape(string(pats),1,[]), if ~isempty(regexp(s,lower(p),'once')), b=true; return; end, end
    end
end
function tf = has_integral_action(name)
    tf=false;
    % (A) explicit integrator block -- continuous OR discrete. 只进掩码/普通子系统, **不跟进链接库块**:
    %     裸积分器无法区分"反馈闭环"vs"前馈(V/f角度生成/SVPWM/PLL)", 跟进链接库会把开环题的前馈积分器误判成闭环(A类假阳性)。
    if ~isempty(find_system(name,'LookUnderMasks','on','BlockType','Integrator')), tf=true; return; end
    if ~isempty(find_system(name,'LookUnderMasks','on','BlockType','DiscreteIntegrator')), tf=true; return; end
    % 遍历(含链接库块)——只认"命名为 PI/PID 控制器"的块, 不认裸积分器. 修 C类假阴性(D012/D023 用 SPS 'Discrete PI Controller' 库块)。
    blks = find_system(name,'LookUnderMasks','on','FollowLinks','on','Type','Block');
    for k=1:numel(blks)
        % (B1) PID/PI/I controller block whose 'Controller' param carries an integral term
        ctrl=""; try, ctrl=upper(string(get_param(blks{k},'Controller'))); catch, end
        if strlength(ctrl)>0 && contains(ctrl,'I'), tf=true; return; end   % PI / PID / I / PID(2DOF)
        % (B2) SPS/library PI/PID controller identified by MaskType (e.g. 'Discrete PI Controller')
        mt=""; try, mt=lower(string(get_param(blks{k},'MaskType'))); catch, end
        if strlength(mt)>0 && ~isempty(regexp(mt,'pi\s*controller|pid controller|pid\b|integral (control|action)','once')), tf=true; return; end
    end
    % (C) continuous transfer function with a pole at the origin (1/s integrator). 不跟进链接库(同A理由)。
    tfs = find_system(name,'LookUnderMasks','on','BlockType','TransferFcn');
    for i=1:numel(tfs)
        den = str2num(get_param(tfs{i},'Denominator')); %#ok<ST2NM>
        if ~isempty(den) && abs(den(end))<1e-9, tf=true; return; end
    end
end

% ---- behavioral helper: steady-state window (last 40%) ----
function [ys,ssmean,pp] = steady(y,t)
    if isempty(t) || numel(t)<3, t=(1:numel(y))'; end
    idx = t >= 0.6*t(end); ys = y(idx); ssmean = mean(ys); pp = max(ys)-min(ys);
end
