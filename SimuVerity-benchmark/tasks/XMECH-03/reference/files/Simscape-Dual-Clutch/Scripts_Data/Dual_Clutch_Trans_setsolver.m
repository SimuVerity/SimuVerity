function Dual_Clutch_Trans_setsolver(mdl,deskreal)
% Copyright 2011-2025 The MathWorks, Inc.

desktop_solver = 'ode23t';

realtime_nonlinIter = '2';
realtime_stepSize = '0.005';
realtime_localSolver = 'NE_BACKWARD_EULER_ADVANCER';
realtime_globalSolver = 'ode1';

f    = Simulink.FindOptions('FollowLinks',0,'LookUnderMasks','none');
solverBlock_pth = Simulink.findBlocks(bdroot, 'SubClassName', 'solver',f);

if strcmpi(deskreal,'desktop')
    set_param(mdl,'Solver',desktop_solver);    
    for svb_i=1:size(solverBlock_pth,1)
        set_param(solverBlock_pth(svb_i), 'UseLocalSolver','off','DoFixedCost','off');
    end
else
    set_param(mdl,'Solver',realtime_globalSolver,'FixedStep','auto');
    for svb_i=1:size(solverBlock_pth,1)
        set_param(solverBlock_pth(svb_i),...
            'UseLocalSolver','on',...
            'DoFixedCost','on',...
            'MaxNonlinIter',realtime_nonlinIter,...
            'LocalSolverChoice',realtime_localSolver,...
            'LocalSolverSampleTime',realtime_stepSize);
    end
end
