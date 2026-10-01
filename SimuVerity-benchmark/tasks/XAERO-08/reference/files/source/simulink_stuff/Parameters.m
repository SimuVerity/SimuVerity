% Some of the initial parameters of the rocket

% Engine stuff
m_dot = 132;
burn_time = 162.25;

% Vehicle
m_payload = 5000;
m_dry = 1360.7;
m_zfw = m_payload + m_dry;

% Conditions at t = t0
v_0 = 0.001;
g = 9.80665;
gam_0 = pi/2;
R_E = 6371e3;
h_0 = 0.001;
x_0 = 0.001;

% Gravity Turn stuff
t_turn = 30;
gam_in = 0.10;