function [uProp_k, uRem_k] = pid_ratio(BIS_k, y_sp, params)
% PID_RATIO A PID controller for propofol and remifentanil ratio
% coadministration with saturation and anti-windup
%
% Inputs:
%   BIS_k   - Current BIS value
%   y_sp    - Setpoint for BIS
%   params  - Struct with fields:
%       Kp, Ti, Td, Ts, N              : PID tuning parameters
%       ratio                          : Remifentanil/propofol ratio
%       uref_p, uref_r                 : Baseline infusion rates
%       sat_pos_p, sat_neg_p           : Saturation limits for propofol
%       sat_pos_r, sat_neg_r           : Saturation limits for remifentanil
%
% Outputs:
%   uProp_k - Control input for propofol
%   uRem_k  - Control input for remifentanil

    persistent y_k1 ei_k1 d_k1 i_k1 init

    if isempty(init)
        y_k1 = BIS_k;
        ei_k1 = 0;
        d_k1 = 0;
        i_k1 = 0;
        init = true;
    end

    % Extract parameters
    Kp = params.Kp;
    Ti = params.Ti;
    Td = params.Td;
    Ts = params.Ts;
    N  = params.N;

    ratio     = params.ratio;
    uref_p    = params.uref_p;
    uref_r    = params.uref_r;
    sat_pos_p = params.sat_pos_p;
    sat_neg_p = params.sat_neg_p;
    sat_pos_r = params.sat_pos_r;
    sat_neg_r = params.sat_neg_r;

    % PID error and terms
    e_k = BIS_k - y_sp;
    i_k = (Kp*Ts*ei_k1 + Ti*i_k1) / Ti;
    d_k = (2*Td*N*Kp*BIS_k - 2*Td*N*Kp*y_k1 - (Ts*N - 2*Td)*d_k1) /...
        (Ts*N + 2*Td);
    p_k = Kp*e_k;
    u_k = p_k + i_k + d_k;

    % Apply baseline offsets
    u_k_p = u_k + uref_p;
    u_k_r = (u_k*ratio) + uref_r;

    % Saturation logic
    if u_k_p > sat_pos_p
        u_sat_p = sat_pos_p;
        sat_k_p = 1;
    elseif u_k_p < sat_neg_p
        u_sat_p = sat_neg_p;
        sat_k_p = 1;
    else
        u_sat_p = u_k_p;
        sat_k_p = 0;
    end

    if u_k_r > sat_pos_r
        u_sat_r = sat_pos_r;
        sat_k_r = 1;
    elseif u_k_r < sat_neg_r
        u_sat_r = sat_neg_r;
        sat_k_r = 1;
    else
        u_sat_r = u_k_r;
        sat_k_r = 0;
    end

    % Anti-windup: clip integral if saturation occurred
    if sat_k_p || sat_k_r
        ei_k1 = 0;
    else
        ei_k1 = e_k;
    end

    % Update memory
    y_k1 = BIS_k;
    d_k1 = d_k;
    i_k1 = i_k;

    % Output
    uProp_k = u_sat_p;
    uRem_k  = u_sat_r;
end