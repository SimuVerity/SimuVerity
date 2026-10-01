% Copyright 2013-2025 The MathWorks, Inc.

cd(fileparts(which(mfilename)))
mdl = 'ssc_hydraulic_lift';
open_system(mdl);
Motor_Conf = {'Custom' 'Standard'};
Valve_Conf = Motor_Conf;
Actuator_Conf = Motor_Conf;
Load_Conf = {'Simple' 'Scissor'};
Control_Conf = {'Algorithm' 'Circuit'};
Solver_Conf = {'Desktop' 'Real Time'};
Hardstop_Conf = {'Adjusted' 'Initial'};

for sc_i = 1:length(Solver_Conf)
    num_runs = 0;
    if(sc_i==1)
        ssc_hydraulic_lift_setsolver(mdl,'desktop')
    else
        ssc_hydraulic_lift_setsolver(mdl,'realtime')
    end
    for hs_n = 1:length(Hardstop_Conf)
        ssc_hydraulic_lift_sethardstop(Hardstop_Conf{hs_n})
        for co_o = 1:length(Control_Conf)
            set_param([bdroot '/Controller'],'OverrideUsingVariant',Control_Conf{co_o});
            for mo_j = 1:length(Motor_Conf)
                set_param([bdroot '/Servo and Controller'],'OverrideUsingVariant',Motor_Conf{mo_j});
                for va_k = 1:length(Valve_Conf)
                    set_param([bdroot '/Valve'],'OverrideUsingVariant',Valve_Conf{va_k});
                    for ac_l = 1:length(Actuator_Conf)
                        set_param([bdroot '/Actuator'],'OverrideUsingVariant',Actuator_Conf{ac_l});
                        for lo_m = 1:length(Load_Conf)
                            set_param([bdroot '/Load'],'OverrideUsingVariant',Load_Conf{lo_m});
                            num_runs = num_runs+1;
                            res_out(num_runs,1:7) = {...
                                num2str(num_runs), Hardstop_Conf{hs_n}, Control_Conf{co_o}, Motor_Conf{mo_j},...
                                Valve_Conf{va_k},  Actuator_Conf{ac_l}, Load_Conf{lo_m}};
                            disp([num2str(sc_i) ' ' Solver_Conf{sc_i} '; H: ' Hardstop_Conf{hs_n} '; C:' Control_Conf{co_o} '; M:' Motor_Conf{mo_j} '; V:' Valve_Conf{va_k}  '; A:' Actuator_Conf{ac_l} '; L: ' Load_Conf{lo_m}]);
                            try
                                sim(mdl);
                                passFail = 'pass';
                            catch
                                Elapsed_Sim_Time = Elapsed_Sim_Time;
                                disp('Simulation Failed')
                                passFail = 'fail';
                            end
                            res_out{num_runs, 7+(sc_i-1)*3+1} = length(tout);
                            res_out{num_runs, 7+(sc_i-1)*3+2} = Elapsed_Sim_Time;
                            res_out{num_runs, 7+(sc_i-1)*3+3} = passFail;
                        end
                    end
                end
            end
        end
    end
end

bdclose(mdl);

res_out_titles = {'Run' 'Hardstop' 'Control' 'Motor' 'Valve' 'Actuator' 'Load' '# Steps' 'Time' 'Pass' '# Steps' 'Time' 'Pass'};

cd(fileparts(which('Hydraulic_Lift_Res.xlsx')));
xlswrite('Hydraulic_Lift_Res.xlsx',res_out_titles,version('-release'),'A2');
xlswrite('Hydraulic_Lift_Res.xlsx',res_out,version('-release'),'A3');
xlswrite('Hydraulic_Lift_Res.xlsx',{['''' datestr(now)]},version('-release'),'B1');



