function ext_xauto_pmsm_param_est_reference_clean_replay_setup(taskId, officialScenariosPath, model)
%EXT_XAUTO_PMSM_PARAM_EST_REFERENCE_CLEAN_REPLAY_SETUP
% Assign the first public operating scenario needed by the current reference
% before its model-level initialization callbacks run.

arguments
    taskId (1,:) char
    officialScenariosPath (1,:) char
    model (1,:) char
end

assert(strcmp(taskId, 'EXT-XAUTO-PMSM-PARAM-EST'), ...
    'SimuVerity:ReferenceSetup:TaskMismatch', ...
    'Reference setup was invoked for the wrong task.');
assert(isfile(officialScenariosPath), ...
    'SimuVerity:ReferenceSetup:OfficialScenariosMissing', ...
    'Official scenarios file is missing.');
document = jsondecode(fileread(officialScenariosPath));
assert(isstruct(document) && isscalar(document) && ...
    isfield(document, 'task_id') && ...
    strcmp(char(string(document.task_id)), taskId) && ...
    isfield(document, 'scenarios') && ~isempty(document.scenarios), ...
    'SimuVerity:ReferenceSetup:OfficialScenariosContract', ...
    'Official scenarios contract is invalid for this task.');
assert(bdIsLoaded(model), ...
    'SimuVerity:ReferenceSetup:ModelNotLoaded', ...
    'PMSM reference model must be loaded before setup.');
set_param(model, 'SimulationMode', 'normal');
localApplyReferenceScenario(document.scenarios(1));
end

function localApplyReferenceScenario(s)
% Keep these assignments byte-for-byte equivalent in value and ordering to
% the current extractor's localApplyReferenceScenario implementation.
Tsim=1e-6; Tob=1/20e3; Rs=s.plant_Rs_ohm;
Ldd_inc=s.plant_Ldd_H; Ldq_inc=s.plant_Ldq_H; Lqq_inc=s.plant_Lqq_H;
L_inc=[Ldd_inc Ldq_inc;Ldq_inc Lqq_inc]; L_inc_inv=L_inc^-1; J=[0 -1;1 0];
Ld_ap=90e-6; Lq_ap=300e-6; Psi_dm=0.054; L_ap=[Ld_ap 0;0 Lq_ap];
inertia=s.plant_inertia_kgm2; damping=s.plant_damping_Nms;
Id0=s.operating_id_A; Iq0=s.operating_iq_A; we0=s.electrical_speed_radps;
Ud0=Rs*Id0-we0*Lq_ap*Iq0; Uq0=Rs*Iq0+we0*(Ld_ap*Id0+Psi_dm);
Umd=s.injection_d_voltage_V; Umq=s.injection_q_voltage_V;
weh=2*pi*s.injection_frequency_Hz;
Tdd=L_inc_inv(1,1); Tdq=L_inc_inv(1,2); Tqq=L_inc_inv(2,2);
R=diag([1 1]); Q=0.01*diag([0.01 0.01 Rs Tdd Tdq Tqq]);
Qx=Q(1:2,1:2); Qp=Q(3:6,3:6);
K_inertia=1e-5; K_damping=1e1;
initial_percentage=s.reference_initial_estimate_scale;
names=who;
for index=1:numel(names)
    assignin("base",names{index},eval(names{index}));
end
end
