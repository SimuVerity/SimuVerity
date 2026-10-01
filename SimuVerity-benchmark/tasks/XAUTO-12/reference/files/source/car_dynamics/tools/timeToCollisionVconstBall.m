function tC = timeToCollisionVconstBall(p, p_obs, v, v_obs, R_A, R_B)
err_p = p - p_obs;
err_v = v - v_obs;

a = dot(err_v', err_v); 
b = dot(err_p', err_v) + dot(err_v', err_p);
c = dot(err_p', err_p) - (R_A + R_B)^2;

if c < 0
    tC = 0.001; % very small, but better to not make 0 as it would create a NaN
    return;
end

tC = roots([a b c]);

tC = min(tC(tC > 0 & isreal(tC)));
end