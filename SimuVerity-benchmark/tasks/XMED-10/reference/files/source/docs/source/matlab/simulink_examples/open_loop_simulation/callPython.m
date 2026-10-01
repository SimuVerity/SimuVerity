function [bis, co, map, tol, nmb] = callPython(u_p,u_r,u_n,u_a,age,height,weight,sex,sampling_time)
% callPython  Interface between Simulink and the Python Anesthesia Simulator.
%
%   [bis, co, map, tol, nmb] = callPython(u_p,u_r,u_n,u_a,age,height,weight,sex,sampling_time)
%   performs one simulation step of the Python patient model.
%
%   Inputs:
%       u_p  - Propofol infusion rate [mg/s]
%       u_r  - Remifentanil infusion rate [µg/s]
%       u_n  - Noradrenaline infusion rate [µg/s]
%       u_a  - Atracurium infusion rate [mg/s]
%       age, height, weight, sex - patient parameters
%       sampling_time - simulation sampling period [s]
%
%   Outputs:
%       bis - Bispectral Index
%       co  - Cardiac Output
%       map - Mean Arterial Pressure
%       tol - Depth of hypnosis metric
%       nmb - Neuromuscular Blockade level
%
%   Notes:
%       - Requires a configured Python environment via pyenv.
%       - Works only in Simulink **Normal** mode (not Accelerator or codegen).

    persistent simulator George

    % Initialize Python environment and patient once
    if isempty(simulator)
        simulator = py.importlib.import_module('python_anesthesia_simulator.simulator');
        George = simulator.Patient([age, height, weight, sex], ts=sampling_time);
    end

    % Run one simulation step
    simulation_tuple = George.one_step( ...
        u_propo=u_p, ...
        u_remi=u_r, ...
        u_nore=u_n, ...
        u_atra=u_a);

    % Convert Python outputs to MATLAB doubles
    simulation_cell = cell(simulation_tuple);
    bis = double(simulation_cell{1});
    co  = double(simulation_cell{2});
    map = double(simulation_cell{3});
    tol = double(simulation_cell{4});
    nmb = double(simulation_cell{5});
end