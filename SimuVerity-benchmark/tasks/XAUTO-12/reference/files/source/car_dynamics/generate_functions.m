%% Clean-up and Setup
% Clear workspace, command window, and close all figures.
clear all; clc; close all

% Define the folder where generated functions will be stored.
fun_folder = "generated_functions/";

% Remove the folder if it exists, then create it and add to the MATLAB path.
if isfolder(fun_folder)
    rmdir(fun_folder, 's');
end
mkdir(fun_folder);
addpath(fun_folder);

%% Define Symbolic Variables
% Declare system and tuning parameters as positive real numbers.
syms R_A R_B alpha_vo alpha_c u_max delta real positive
syms t theta tanPhi v a real

% Define symbolic state variables for agent A (position, velocity, and control input)
p_A = sym('p_A%d', [2 1],'real');
v_A = v * [cos(theta); sin(theta)]; 
u_A = [tanPhi; a];

% Define symbolic variables for agent B (position and velocity)
p_B = sym('p_B%d', [2 1],'real');
v_B = sym('v_B%d', [2 1],'real');

% Define the state vector (for car dynamics model) and its derivative.
x = [p_A; theta; v]; 
dx_dt = [v_A; v/1*u_A(1); u_A(2)];

% Define relative position
p_AB = p_B - p_A;
d_AB = sqrt(dot(p_AB', p_AB));
v_AB = v_B - v_A + eps;      % Relative velocity; add eps to avoid division-by-zero.
r = R_A + R_B;               % Combined radii (or safe distance measure).

%% Velocity Obstacle (VO) - Control Barrier Function (CBF)
% Compute the sine and cosine of the cone semi-angle for the velocity obstacle.
sinGamma = r / d_AB;
cosGamma = sqrt(d_AB^2 - r^2) / d_AB;

% Define the VO-CBF.
h_vo = d_AB * sqrt(dot(v_AB, v_AB)) * cosGamma + dot(p_AB', v_AB);

% Compute the gradient of cVO with respect to the state vector.
grad_h_vo = jacobian(h_vo, x)';

% Compute the time derivative of cVO using the chain rule.
dh_vo_dt = dot(grad_h_vo', dx_dt);

% Define the VO inequality condition using a tunable parameter kappa.
h_vo_inequality = dh_vo_dt + alpha_vo * h_vo;

% Package the required symbolic variables as function inputs.
args_h_vo = {p_A, p_B, theta, v, v_B, u_A, R_A, R_B, alpha_vo};

% It can be checked how the inequality is linear on the control
assert(isempty(nonzeros(hessian(h_vo_inequality, u_A))));
assert(~isempty(nonzeros(jacobian(h_vo_inequality, u_A))));

% Generate MATLAB function files for VO computations.
matlabFunction(h_vo, "File", fun_folder + "h_vo_fun", "Vars", args_h_vo);
matlabFunction(grad_h_vo, "File", fun_folder + "grad_h_vo_fun", "Vars", args_h_vo);
matlabFunction(dh_vo_dt, "File", fun_folder + "dh_vo_dt_fun", "Vars", args_h_vo);
matlabFunction(h_vo_inequality, "File", fun_folder + "h_vo_inequality_fun", "Vars", args_h_vo);

%% Safe Control Barrier Function (SCBF) for Constrained Inputs
% This SCBF accounts for limits on the maximum control input (u_max).

% Compute the relative velocity component along the line connecting agents.
v_ij = dot(v_AB, p_AB / d_AB);

% Define the SCBF that incorporates a deceleration term based on u_max.
h_scbf = d_AB - delta - (v_ij^2) / (2 * u_max);
grad_h_scbf = jacobian(h_scbf, x)';  
dh_scbf_dt = dot(grad_h_scbf', dx_dt); 

% Define the SCBF inequality condition.
h_scbf_ineq = dh_scbf_dt + alpha_c * h_scbf;

% Define the inputs for the SCBF functions.
args_hscbf = {p_A, p_B, theta, v, v_B, u_A, u_max, delta, alpha_c};

% It can be checked how the inequality is linear on the control
assert(isempty(nonzeros(hessian(h_scbf_ineq, u_A))));
assert(~isempty(nonzeros(jacobian(h_scbf_ineq, u_A))));

% Generate MATLAB function files for SCBF computations.
matlabFunction(h_scbf, "File", fun_folder + "h_scbf_fun", "Vars", args_hscbf);
matlabFunction(grad_h_scbf, "File", fun_folder + "grad_h_scbf_fun", "Vars", args_hscbf);
matlabFunction(dh_scbf_dt, "File", fun_folder + "dh_scbf_dt_fun", "Vars", args_hscbf);
matlabFunction(h_scbf_ineq, "File", fun_folder + "h_scbf_ineq_fun", "Vars", args_hscbf);