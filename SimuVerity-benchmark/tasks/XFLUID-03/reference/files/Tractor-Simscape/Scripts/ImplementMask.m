% This code sets the parameters of Implement block and disables/ enables
% implement block connectivity based on Implement mask parameter values.

% Copyright 2024 The MathWorks, Inc.

%%
maskObj = Simulink.Mask.get(gcb);
methodForceComputation = maskObj.getParameter('methodForceComputation');
typeImplement = maskObj.getParameter('typeImplement');
implementBlockPath = [gcb,'/Implement'];
wImplement = get_param(gcb,'value@widthImplement');
nTools = get_param(gcb,'value@numberTools');
alpha = get_param(gcb,'value@angleRake');
draftForce = get_param(gcb,'value@vectorDraft');
verticalForce = get_param(gcb,'value@vectorVF');
velocity = get_param(gcb,'value@vectorVelocity');
widthImplement = maskObj.getParameter('widthImplement');
numberTools = maskObj.getParameter('numberTools');
angleRake = maskObj.getParameter('angleRake');
vectorDraft = maskObj.getParameter('vectorDraft');
vectorVF = maskObj.getParameter('vectorVF');
vectorVelocity = maskObj.getParameter('vectorVelocity');

if strcmp(methodForceComputation.Value,'Specify vectors for draft force, vertical force and velocity')
    set_param(gcb,'Tag','Custom Load Cycle')
    typeImplement.Visible = 'off';
    widthImplement.Visible = 'off';
    numberTools.Visible = 'off';
    angleRake.Visible = 'off';
    vectorDraft.Visible = 'on';
    vectorVF.Visible = 'on';
    vectorVelocity.Visible = 'on';
    set_param(implementBlockPath,'velocity_vector',mat2str(velocity));
    set_param(implementBlockPath,'draft_vector',mat2str(draftForce));
    set_param(implementBlockPath,'VF_vector',mat2str(verticalForce));

elseif strcmp(methodForceComputation.Value,'Draft force prediction based on ASABE D497.5 standard')
    set_param(gcb,'Tag','ASABE 497.5 Load Cycle')
    typeImplement.Visible = 'on';
    
switch typeImplement.Value
    case 'Subsoiler - narrow point'           
    widthImplement.Visible = 'off';
    numberTools.Visible = 'on';
    angleRake.Visible = 'on';
    vectorDraft.Visible = 'off';
    vectorVF.Visible = 'off';
    vectorVelocity.Visible = 'off';
    set_param(implementBlockPath,'type_implement','ImplementType.Subsoiler');
    set_param(implementBlockPath,'number_tools',mat2str(nTools));
    set_param(implementBlockPath,'rake_angle',mat2str(alpha));
    case 'Chisel Plow - 5 cm straight point'
    widthImplement.Visible = 'off';
    numberTools.Visible = 'on';
    angleRake.Visible = 'on';
    vectorDraft.Visible = 'off';
    vectorVF.Visible = 'off';
    vectorVelocity.Visible = 'off';
    set_param(implementBlockPath,'type_implement','ImplementType.ChiselPlow');
    set_param(implementBlockPath,'number_tools',mat2str(nTools));
    set_param(implementBlockPath,'rake_angle',mat2str(alpha));
    case 'Field Cultivator for primary tillage'
    widthImplement.Visible = 'off';
    numberTools.Visible = 'on';
    angleRake.Visible = 'on';
    vectorDraft.Visible = 'off';
    vectorVF.Visible = 'off';
    vectorVelocity.Visible = 'off';
    set_param(implementBlockPath,'type_implement','ImplementType.FieldCultivator');
    set_param(implementBlockPath,'number_tools',mat2str(nTools));
    set_param(implementBlockPath,'rake_angle',mat2str(alpha));
    case 'Moldboard Plow'  
    widthImplement.Visible = 'on';
    numberTools.Visible = 'off';
    angleRake.Visible = 'on';
    vectorDraft.Visible = 'off';
    vectorVF.Visible = 'off';
    vectorVelocity.Visible = 'off';
    set_param(implementBlockPath,'type_implement','ImplementType.MoldboardPlow');
    wImplement = get_param(gcb,'value@widthImplement');
    set_param(implementBlockPath,'width_implement',mat2str(wImplement));
    set_param(implementBlockPath,'width_implement',mat2str(wImplement));
    set_param(implementBlockPath,'rake_angle',mat2str(alpha));
    case 'Sweep Plow for primary tillage'
    widthImplement.Visible = 'on';
    numberTools.Visible = 'off';
    angleRake.Visible = 'on';
    vectorDraft.Visible = 'off';
    vectorVF.Visible = 'off';
    vectorVelocity.Visible = 'off';
    set_param(implementBlockPath,'type_implement','ImplementType.SweepPlow');
    set_param(implementBlockPath,'width_implement',mat2str(wImplement));
    set_param(implementBlockPath,'rake_angle',mat2str(alpha));
end
end

implementPortConnectivity(gcb,methodForceComputation);