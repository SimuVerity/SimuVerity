% Copyright 2016-2025 The MathWorks(TM), Inc.

if (exist('youBot_optres_friction.mat','file'))
    load youBot_optres_friction.mat
    youBot_optim_plotEExyz
else
    web('youBot_optim_res_Friction.html');
end